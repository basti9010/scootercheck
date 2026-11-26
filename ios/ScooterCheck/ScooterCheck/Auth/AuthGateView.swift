import SwiftUI

/// Login / Registrierung / Warte auf Freigabe / Admin-Userliste.
struct AuthGateView: View {
    @ObservedObject var auth: AuthSessionStore
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var busy = false
    @State private var showAdmin = false

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
        .sheet(isPresented: $showAdmin) {
            NavigationStack {
                AdminHubView(auth: auth)
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
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .scootField()
                }

                Text("Caps Lock aus beim Einfügen aus dem Passwortmanager — sonst werden Groß/Klein vertauscht.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                Button("Admin") { showAdmin = true }
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
        let mail = AuthCredentialsNormalizer.normalizedEmail(email)
        let pass = AuthCredentialsNormalizer.normalizedPassword(password)
        email = mail
        if mode == .login {
            await auth.login(email: mail, password: pass)
            // Caps Lock oft vertauscht Groß/Klein beim Einfügen — einmal mit getauschtem Case retry.
            if !auth.isLoggedIn,
               AuthCredentialsNormalizer.isWrongCredentialsMessage(auth.lastError) {
                let swapped = AuthCredentialsNormalizer.toggledLetterCase(pass)
                if swapped != pass {
                    await auth.login(email: mail, password: swapped)
                    if auth.isLoggedIn {
                        password = swapped
                    }
                }
            }
        } else {
            await auth.register(email: mail, password: pass, displayName: displayName)
        }
    }
}

