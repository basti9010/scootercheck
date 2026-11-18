import SwiftUI

/// Einstieg Admin: getrennte Bereiche (Benutzer, Domains, später erweiterbar).
struct AdminHubView: View {
    @ObservedObject var auth: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                VStack(alignment: .leading, spacing: Theme.Space.titleStack) {
                    PageTitle(text: "Admin")
                    Text("Benutzer, Domains und weitere Verwaltung")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Space.listGap) {
                    NavigationLink {
                        AdminUsersView(auth: auth)
                    } label: {
                        adminLinkRow(
                            title: "Benutzer",
                            subtitle: "Registrierungen freigeben, ablehnen oder deaktivieren.",
                            systemImage: "person.badge.shield.checkmark"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AdminDomainsView(auth: auth)
                    } label: {
                        adminLinkRow(
                            title: "Domains",
                            subtitle: "E-Mail-Domains freigeben, die sich registrieren dürfen.",
                            systemImage: "at.circle"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .scootPagePadding()
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
        }
    }

    private func adminLinkRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.Icon.function, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.Icon.function + 2, height: Theme.Icon.function + 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, Theme.Space.cardPadding)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.Control.hairline)
        )
    }
}

struct AdminUsersView: View {
    @ObservedObject var auth: AuthSessionStore
    @State private var users: [AuthUser] = []
    @State private var filter: AuthUserStatus? = .pending
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).foregroundStyle(Theme.danger)
            }

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

struct AdminDomainsView: View {
    @ObservedObject var auth: AuthSessionStore
    @State private var domains: [AuthDomain] = []
    @State private var newDomain = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).foregroundStyle(Theme.danger)
            }

            Section {
                Text("Nur diese Domains dürfen sich registrieren (nach dem @). Ohne Eintrag ist die Registrierung gesperrt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section("Neue Domain") {
                HStack {
                    Text("@")
                        .foregroundStyle(.secondary)
                    TextField("polizei.bayern.de", text: $newDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Freigeben") {
                        Task { await addDomain() }
                    }
                    .disabled(busy || newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Freigegeben") {
                if domains.isEmpty {
                    Text("Noch keine Domains")
                        .foregroundStyle(.secondary)
                }
                ForEach(domains) { item in
                    HStack {
                        Text("@\(item.domain)")
                        Spacer()
                        Button(role: .destructive) {
                            Task { await removeDomain(item.domain) }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Domains")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            domains = try await AuthAPIClient.listDomains(token: token)
            errorText = nil
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    private func addDomain() async {
        guard let token = auth.token else { return }
        let value = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        defer { busy = false }
        do {
            _ = try await AuthAPIClient.addDomain(value, token: token)
            newDomain = ""
            await reload()
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    private func removeDomain(_ domain: String) async {
        guard let token = auth.token else { return }
        do {
            try await AuthAPIClient.removeDomain(domain, token: token)
            await reload()
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }
}
