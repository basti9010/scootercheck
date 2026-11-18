import SwiftUI

/// Login / Registrierung / Warte auf Freigabe / Admin-Userliste.
struct AuthGateView: View {
    @ObservedObject var auth: AuthSessionStore
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var busy = false
    @State private var showAdminUsers = false

    private enum Mode: String, CaseIterable {
        case login = "Anmelden"
        case register = "Registrieren"
    }

    var body: some View {
        Group {
            if auth.isBootstrapping {
                ProgressView("Sitzung…")
                    .tint(Theme.accent)
            } else if auth.canUseApp {
                ContentView()
                    .environmentObject(auth)
            } else if auth.isLoggedIn {
                pendingView
            } else {
                authForm
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .task { await auth.bootstrap() }
        .sheet(isPresented: $showAdminUsers) {
            NavigationStack {
                AdminUsersView(auth: auth)
            }
        }
    }

    private var authForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("ScooterCheck")
                    .font(Theme.brandWordmark)
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 40)

                Text("Konto für Auslesen & Forensik")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)

                Picker("Modus", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    if mode == .register {
                        TextField("Name (optional)", text: $displayName)
                            .textContentType(.name)
                            .scootField()
                    }
                    TextField("E-Mail", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .scootField()
                    SecureField("Passwort (min. 8)", text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)
                        .scootField()
                }

                if let err = auth.lastError {
                    Text(err)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if busy {
                        ProgressView().tint(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Control.buttonMinHeight)
                    } else {
                        Text(mode == .login ? "Anmelden" : "Registrieren")
                            .font(Theme.button)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.Control.buttonMinHeight)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
                .background(Theme.accent.opacity(busy ? 0.5 : 1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .disabled(busy || email.isEmpty || password.count < 8)

                Text("Nach der Registrierung schaltet ein Admin dein Konto frei.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .scootPagePadding()
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var pendingView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: auth.user?.status == .rejected ? "xmark.seal" : "hourglass")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(pendingTitle)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(pendingBody)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if auth.isAdmin {
                Button("Benutzer freischalten") { showAdminUsers = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }

            Button("Status aktualisieren") {
                Task { await auth.refreshMe() }
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)

            Button("Abmelden", role: .destructive) { auth.logout() }
                .padding(.top, 8)
            Spacer()
            AppCopyrightFooter()
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var pendingTitle: String {
        switch auth.user?.status {
        case .rejected: return "Konto abgelehnt"
        case .disabled: return "Konto deaktiviert"
        default: return "Freischaltung ausstehend"
        }
    }

    private var pendingBody: String {
        switch auth.user?.status {
        case .rejected:
            return "Dein Zugang wurde nicht freigegeben. Bei Bedarf den Admin kontaktieren."
        case .disabled:
            return "Dein Konto ist deaktiviert."
        default:
            return "Dein Konto ist registriert und wartet auf Freigabe. Danach kannst du ScooterCheck nutzen."
        }
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .login {
            await auth.login(email: mail, password: password)
        } else {
            await auth.register(email: mail, password: password, displayName: displayName)
        }
    }
}

struct AdminUsersView: View {
    @ObservedObject var auth: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var users: [AuthUser] = []
    @State private var filter: AuthUserStatus? = .pending
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        List {
            Picker("Filter", selection: $filter) {
                Text("Offen").tag(Optional.some(AuthUserStatus.pending))
                Text("Aktiv").tag(Optional.some(AuthUserStatus.active))
                Text("Alle").tag(Optional<AuthUserStatus>.none)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .onChange(of: filter) { _ in
                Task { await reload() }
            }

            if let errorText {
                Text(errorText).foregroundStyle(Theme.danger)
            }

            ForEach(users) { user in
                VStack(alignment: .leading, spacing: 8) {
                    Text(user.displayName?.isEmpty == false ? user.displayName! : user.email)
                        .font(.headline)
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(user.role.rawValue) · \(user.status.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)

                    HStack {
                        if user.status == .pending {
                            Button("Freigeben") {
                                Task { await act(approve: true, user) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Ablehnen", role: .destructive) {
                                Task { await act(approve: false, user) }
                            }
                        } else if user.status == .active, user.role != .admin {
                            Button("Deaktivieren", role: .destructive) {
                                Task { await disable(user) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Benutzer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(busy)
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        guard let token = auth.token else { return }
        busy = true
        defer { busy = false }
        do {
            users = try await AuthAPIClient.listUsers(token: token, status: filter)
            errorText = nil
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    private func act(approve: Bool, _ user: AuthUser) async {
        guard let token = auth.token else { return }
        do {
            if approve {
                _ = try await AuthAPIClient.approve(userId: user.id, token: token)
            } else {
                _ = try await AuthAPIClient.reject(userId: user.id, token: token)
            }
            await reload()
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    private func disable(_ user: AuthUser) async {
        guard let token = auth.token else { return }
        do {
            _ = try await AuthAPIClient.disable(userId: user.id, token: token)
            await reload()
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }
}
