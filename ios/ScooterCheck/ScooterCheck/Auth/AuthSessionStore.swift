import Foundation
import SwiftUI

@MainActor
final class AuthSessionStore: ObservableObject {
    static let shared = AuthSessionStore()

    @Published private(set) var token: String?
    @Published private(set) var user: AuthUser?
    @Published private(set) var isBootstrapping = true
    @Published private(set) var lastAuthError: AuthAPIError?
    @Published var lastError: String?

    /// True when bootstrap kept a prior session despite transient network failure.
    @Published private(set) var isOfflineSession = false

    private let tokenStore: AuthTokenStoring
    private let userCache: AuthUserCaching
    private let remote: AuthRemoteClient

    var isLoggedIn: Bool { token != nil && user != nil }

    /// Local investigation / BLE / history: active cached or live user (offline-capable).
    var canUseApp: Bool { AuthSessionPolicy.allowsLocalFeatures(accessTier) }

    /// Alias — local features when a previously valid active session exists.
    var canUseLocalFeatures: Bool { canUseApp }

    /// Bearer present for server attempts; server still validates. Offline UI uses `accessTier`.
    var hasBearerToken: Bool {
        guard let token, !token.isEmpty else { return false }
        return true
    }

    /// Online server-API tier (false while offline / local-only).
    var canCallServerAPIs: Bool { AuthSessionPolicy.allowsServerAPI(accessTier) }

    var isAdmin: Bool { user?.isAdmin == true }

    var accessTier: AuthSessionPolicy.AccessTier {
        AuthSessionPolicy.accessTier(
            hasToken: hasBearerToken,
            user: user,
            serverReachable: !isOfflineSession && hasBearerToken
        )
    }

    private init() {
        self.tokenStore = KeychainAuthTokenStore()
        self.userCache = UserDefaultsAuthUserCache()
        self.remote = LiveAuthRemoteClient()
        token = tokenStore.loadToken()
        user = userCache.loadUser()
    }

    /// Test / DI entry — does not touch the shared singleton.
    init(
        tokenStore: AuthTokenStoring,
        userCache: AuthUserCaching,
        remote: AuthRemoteClient,
        bootstrapping: Bool = false
    ) {
        self.tokenStore = tokenStore
        self.userCache = userCache
        self.remote = remote
        self.isBootstrapping = bootstrapping
        token = tokenStore.loadToken()
        user = userCache.loadUser()
    }

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        guard let token else {
            user = nil
            userCache.deleteUser()
            isOfflineSession = false
            return
        }
        do {
            let me = try await remote.me(token: token)
            user = me
            userCache.saveUser(me)
            lastAuthError = nil
            lastError = nil
            isOfflineSession = false
        } catch {
            handleSessionFailure(Self.coerce(error))
        }
    }

    func register(email: String, password: String, displayName: String?) async {
        lastError = nil
        lastAuthError = nil
        do {
            let response = try await remote.register(
                email: email,
                password: password,
                displayName: displayName
            )
            apply(response)
        } catch {
            let authError = Self.coerce(error)
            lastAuthError = authError
            lastError = authError.message
        }
    }

    func login(email: String, password: String) async {
        lastError = nil
        lastAuthError = nil
        do {
            let response = try await remote.login(email: email, password: password)
            apply(response)
        } catch {
            let authError = Self.coerce(error)
            lastAuthError = authError
            lastError = authError.message
        }
    }

    func refreshMe() async {
        guard let token else { return }
        do {
            let me = try await remote.me(token: token)
            user = me
            userCache.saveUser(me)
            lastAuthError = nil
            lastError = nil
            isOfflineSession = false
        } catch {
            handleSessionFailure(Self.coerce(error))
        }
    }

    func changePassword(current: String, new: String) async throws {
        guard hasBearerToken, let token else {
            throw AuthAPIError(kind: .forbidden, message: "Nicht angemeldet", statusCode: 401)
        }
        do {
            try await remote.changePassword(current: current, new: new, token: token)
            lastAuthError = nil
            lastError = nil
        } catch {
            let authError = Self.coerce(error)
            lastAuthError = authError
            lastError = authError.message
            throw authError
        }
    }

    func logout() {
        clearSession()
        lastAuthError = nil
        lastError = nil
        isOfflineSession = false
    }

    /// Explicit gate helper: admin UI still requires live `isAdmin` + admin tier when online.
    func requireAdmin() -> Bool {
        isAdmin && AuthSessionPolicy.allowsAdminAPI(accessTier)
    }

    /// Server-bound call sites should refuse when no bearer / not in server tier.
    func requireServerAuth() throws {
        guard hasBearerToken else {
            throw AuthAPIError(
                kind: .forbidden,
                message: "Anmeldung erforderlich für Server-Funktionen.",
                statusCode: 401
            )
        }
        guard canCallServerAPIs else {
            throw AuthAPIError(
                kind: .unreachable,
                message: "Server nicht erreichbar — lokale Daten bleiben verfügbar.",
                statusCode: nil
            )
        }
    }

    private func handleSessionFailure(_ authError: AuthAPIError) {
        let policy = AuthSessionPolicy.bootstrapFailureAction(
            httpStatus: authError.statusCode,
            isTransportFailure: authError.isTransientNetworkFailure
        )
        let clear = authError.shouldClearSession || policy == .clearSession
        if clear {
            clearSession()
            lastAuthError = authError
            lastError = authError.message
            isOfflineSession = false
        } else {
            // Keep token + cached user so local features stay available.
            if user == nil, let cached = userCache.loadUser() {
                user = cached
            }
            lastAuthError = authError
            lastError = authError.message
            isOfflineSession = true
        }
    }

    private func apply(_ response: AuthResponse) {
        token = response.accessToken
        user = response.user
        tokenStore.saveToken(response.accessToken)
        userCache.saveUser(response.user)
        lastAuthError = nil
        lastError = nil
        isOfflineSession = false
    }

    private func clearSession() {
        token = nil
        user = nil
        tokenStore.deleteToken()
        userCache.deleteUser()
        isOfflineSession = false
    }

    private static func coerce(_ error: Error) -> AuthAPIError {
        if let auth = error as? AuthAPIError { return auth }
        return AuthErrorMapper.mapURLFailure(error)
    }
}
