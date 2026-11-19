import Foundation
import SwiftUI

@MainActor
final class AuthSessionStore: ObservableObject {
    static let shared = AuthSessionStore()

    @Published private(set) var token: String?
    @Published private(set) var user: AuthUser?
    @Published private(set) var isBootstrapping = true
    @Published var lastError: String?

    /// Legacy UserDefaults key — migrated once into Keychain then cleared.
    private let legacyTokenKey = "scootercheck.auth.token"

    var isLoggedIn: Bool { token != nil && user != nil }
    var canUseApp: Bool { user?.isActive == true }
    var isAdmin: Bool { user?.isAdmin == true }

    private init() {
        if let keychain = AuthKeychainStore.loadToken(), !keychain.isEmpty {
            token = keychain
        } else if let legacy = UserDefaults.standard.string(forKey: legacyTokenKey),
                  !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // One-shot migration: only wipe UserDefaults after Keychain save succeeds.
            token = legacy
            if AuthKeychainStore.saveToken(legacy) {
                UserDefaults.standard.removeObject(forKey: legacyTokenKey)
            }
            // If Keychain save fails, keep legacy UserDefaults so the session is not lost.
        }
    }

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        guard let token else {
            user = nil
            return
        }
        do {
            user = try await AuthAPIClient.me(token: token)
            lastError = nil
        } catch {
            clearSession()
            lastError = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    func register(email: String, password: String, displayName: String?) async {
        lastError = nil
        do {
            let response = try await AuthAPIClient.register(
                email: email,
                password: password,
                displayName: displayName
            )
            apply(response)
        } catch {
            lastError = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    func login(email: String, password: String) async {
        lastError = nil
        do {
            let response = try await AuthAPIClient.login(email: email, password: password)
            apply(response)
        } catch {
            lastError = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    func refreshMe() async {
        guard let token else { return }
        do {
            user = try await AuthAPIClient.me(token: token)
            lastError = nil
        } catch {
            lastError = (error as? AuthAPIError)?.message ?? error.localizedDescription
        }
    }

    func changePassword(current: String, new: String) async throws {
        guard let token else {
            throw AuthAPIError(message: "Nicht angemeldet")
        }
        try await AuthAPIClient.changePassword(current: current, new: new, token: token)
        lastError = nil
    }

    func logout() {
        clearSession()
    }

    private func apply(_ response: AuthResponse) {
        token = response.accessToken
        user = response.user
        if AuthKeychainStore.saveToken(response.accessToken) {
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        }
        lastError = nil
    }

    private func clearSession() {
        token = nil
        user = nil
        AuthKeychainStore.deleteToken()
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
    }
}
