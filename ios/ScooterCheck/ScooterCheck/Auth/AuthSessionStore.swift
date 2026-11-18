import Foundation
import SwiftUI

@MainActor
final class AuthSessionStore: ObservableObject {
    static let shared = AuthSessionStore()

    @Published private(set) var token: String?
    @Published private(set) var user: AuthUser?
    @Published private(set) var isBootstrapping = true
    @Published var lastError: String?

    private let tokenKey = "scootercheck.auth.token"

    var isLoggedIn: Bool { token != nil && user != nil }
    var canUseApp: Bool { user?.isActive == true }
    var isAdmin: Bool { user?.isAdmin == true }

    private init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
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

    func logout() {
        clearSession()
    }

    private func apply(_ response: AuthResponse) {
        token = response.accessToken
        user = response.user
        UserDefaults.standard.set(response.accessToken, forKey: tokenKey)
        lastError = nil
    }

    private func clearSession() {
        token = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
