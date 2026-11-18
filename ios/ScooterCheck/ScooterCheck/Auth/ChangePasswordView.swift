import SwiftUI

/// Eigenes Passwort ändern (aktuelles + neues).
struct ChangePasswordView: View {
    @ObservedObject var auth: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var successText: String?

    var body: some View {
        Form {
            Section {
                SecureField("Aktuelles Passwort", text: $currentPassword)
                    .textContentType(.password)
                SecureField("Neues Passwort (min. 8)", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Neues Passwort wiederholen", text: $confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                Text("Nach dem Ändern bleibst du angemeldet.")
                    .font(.caption)
            }

            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(Theme.danger)
                }
            }
            if let successText {
                Section {
                    Text(successText).foregroundStyle(Theme.accent)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if busy {
                        ProgressView()
                    } else {
                        Text("Passwort speichern")
                    }
                }
                .disabled(busy || !canSubmit)
            }
        }
        .navigationTitle("Passwort ändern")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var canSubmit: Bool {
        currentPassword.count >= 1
            && newPassword.count >= 8
            && newPassword == confirmPassword
            && newPassword != currentPassword
    }

    private func submit() async {
        guard canSubmit else {
            if newPassword != confirmPassword {
                errorText = "Neue Passwörter stimmen nicht überein"
            } else if newPassword.count < 8 {
                errorText = "Neues Passwort mindestens 8 Zeichen"
            } else {
                errorText = "Angaben prüfen"
            }
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await auth.changePassword(current: currentPassword, new: newPassword)
            errorText = nil
            successText = "Passwort geändert."
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            successText = nil
            errorText = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }
}
