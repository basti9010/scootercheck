import SwiftUI

/// Admin: Benutzer bearbeiten (Name, E-Mail, Rolle, Status).
struct AdminUserEditView: View {
    @ObservedObject var auth: AuthSessionStore
    let user: AuthUser
    var onSaved: (AuthUser) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var role: AuthUserRole = .user
    @State private var status: AuthUserStatus = .pending
    @State private var busy = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Konto") {
                TextField("Anzeigename", text: $displayName)
                    .textContentType(.name)
                TextField("E-Mail", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Rechte") {
                Picker("Rolle", selection: $role) {
                    Text("Benutzer").tag(AuthUserRole.user)
                    Text("Admin").tag(AuthUserRole.admin)
                }
                Picker("Status", selection: $status) {
                    Text("Offen").tag(AuthUserStatus.pending)
                    Text("Aktiv").tag(AuthUserStatus.active)
                    Text("Abgelehnt").tag(AuthUserStatus.rejected)
                    Text("Gesperrt").tag(AuthUserStatus.disabled)
                }
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(Theme.danger)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if busy {
                        ProgressView()
                    } else {
                        Text("Speichern")
                    }
                }
                .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                Button("Passwort zurücksetzen") {
                    Task { await resetPassword() }
                }
                .disabled(busy)

                if status != .disabled {
                    Button("Sperren", role: .destructive) {
                        status = .disabled
                        Task { await save() }
                    }
                    .disabled(busy || user.id == auth.user?.id)
                } else {
                    Button("Entsperren") {
                        status = .active
                        Task { await save() }
                    }
                    .disabled(busy)
                }

                Button("Benutzer löschen", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(busy || user.id == auth.user?.id)
            }
        }
        .navigationTitle("Benutzer bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            displayName = user.displayName ?? ""
            email = user.email
            role = user.role
            status = user.status
        }
        .confirmationDialog(
            "Benutzer wirklich löschen?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                Task { await deleteUser() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(user.email)
        }
    }

    private func save() async {
        guard let token = auth.token else { return }
        busy = true
        defer { busy = false }
        do {
            let updated = try await AuthAPIClient.updateUser(
                userId: user.id,
                token: token,
                displayName: displayName,
                role: role,
                status: status,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            errorText = nil
            onSaved(updated)
            dismiss()
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    private func resetPassword() async {
        guard let token = auth.token else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await AuthAPIClient.resetPassword(userId: user.id, token: token)
            if let temp = result.temporaryPassword {
                errorText = nil
                // Surface via errorText style but as info — keep simple
                errorText = "Temp-Passwort: \(temp)"
            }
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    private func deleteUser() async {
        guard let token = auth.token else { return }
        busy = true
        defer { busy = false }
        do {
            try await AuthAPIClient.deleteUser(userId: user.id, token: token)
            onSaved(user) // parent reloads
            dismiss()
        } catch {
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }
}
