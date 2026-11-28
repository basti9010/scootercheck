import XCTest
@testable import ScooterCheck

@MainActor
final class AuthSessionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AuthSessionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSuccessfulLoginStoresTokenAndUser() async {
        let remote = MockAuthRemote()
        remote.loginResult = .success(Self.sampleResponse(status: .active))
        let store = makeStore(remote: remote)

        await store.login(email: "user@example.com", password: "password1")

        XCTAssertTrue(store.isLoggedIn)
        XCTAssertTrue(store.canUseApp)
        XCTAssertTrue(store.canUseLocalFeatures)
        XCTAssertTrue(store.hasBearerToken)
        XCTAssertTrue(store.canCallServerAPIs)
        XCTAssertEqual(store.accessTier, .serverAPI)
        XCTAssertEqual(store.user?.email, "user@example.com")
        XCTAssertEqual(store.token, "tok-live")
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isOfflineSession)
    }

    func testBadCredentialsDoesNotCreateSession() async {
        let remote = MockAuthRemote()
        remote.loginResult = .failure(
            AuthAPIError(kind: .invalidCredentials, message: "E-Mail oder Passwort falsch", statusCode: 401)
        )
        let store = makeStore(remote: remote)

        await store.login(email: "user@example.com", password: "wrong-pass")

        XCTAssertFalse(store.isLoggedIn)
        XCTAssertNil(store.token)
        XCTAssertEqual(store.lastAuthError?.kind, .invalidCredentials)
        XCTAssertTrue(AuthCredentialsNormalizer.isWrongCredentials(store.lastAuthError))
    }

    func testRestoredSessionFromCacheThenMeSuccess() async {
        let tokens = InMemoryAuthTokenStore(defaults: defaults)
        tokens.saveToken("tok-restored")
        let cache = UserDefaultsAuthUserCache(defaults: defaults)
        cache.saveUser(Self.sampleUser(status: .active))

        let remote = MockAuthRemote()
        remote.meResult = .success(Self.sampleUser(status: .active, email: "fresh@example.com"))
        let store = AuthSessionStore(tokenStore: tokens, userCache: cache, remote: remote)

        XCTAssertEqual(store.token, "tok-restored")
        XCTAssertEqual(store.user?.email, "user@example.com")

        await store.bootstrap()

        XCTAssertEqual(store.user?.email, "fresh@example.com")
        XCTAssertTrue(store.canUseApp)
        XCTAssertFalse(store.isOfflineSession)
        XCTAssertNil(store.lastError)
    }

    func testExpiredOrRevokedClearsSession() async {
        let tokens = InMemoryAuthTokenStore(defaults: defaults)
        tokens.saveToken("tok-dead")
        let cache = UserDefaultsAuthUserCache(defaults: defaults)
        cache.saveUser(Self.sampleUser(status: .active))

        let remote = MockAuthRemote()
        remote.meResult = .failure(
            AuthAPIError(kind: .expired, message: "Sitzung abgelaufen", statusCode: 401)
        )
        let store = AuthSessionStore(tokenStore: tokens, userCache: cache, remote: remote)

        await store.bootstrap()

        XCTAssertNil(store.token)
        XCTAssertNil(store.user)
        XCTAssertNil(tokens.loadToken())
        XCTAssertNil(cache.loadUser())
        XCTAssertFalse(store.canUseApp)
        XCTAssertEqual(store.lastAuthError?.kind, .expired)

        // Revoked path
        tokens.saveToken("tok-revoked")
        cache.saveUser(Self.sampleUser(status: .active))
        let store2 = AuthSessionStore(tokenStore: tokens, userCache: cache, remote: remote)
        remote.meResult = .failure(
            AuthAPIError(kind: .revoked, message: "widerrufen", statusCode: 401)
        )
        await store2.bootstrap()
        XCTAssertNil(store2.token)
        XCTAssertEqual(store2.lastAuthError?.kind, .revoked)
    }

    func testNetworkErrorDoesNotClearSession() async {
        let tokens = InMemoryAuthTokenStore(defaults: defaults)
        tokens.saveToken("tok-keep")
        let cache = UserDefaultsAuthUserCache(defaults: defaults)
        cache.saveUser(Self.sampleUser(status: .active))

        let remote = MockAuthRemote()
        remote.meResult = .failure(
            AuthAPIError(kind: .noInternet, message: "Keine Internetverbindung")
        )
        let store = AuthSessionStore(tokenStore: tokens, userCache: cache, remote: remote)

        await store.bootstrap()

        XCTAssertEqual(store.token, "tok-keep")
        XCTAssertEqual(tokens.loadToken(), "tok-keep")
        XCTAssertTrue(store.canUseLocalFeatures)
        XCTAssertTrue(store.isOfflineSession)
        XCTAssertEqual(store.accessTier, .localOnly)
        XCTAssertFalse(store.canCallServerAPIs)
        XCTAssertEqual(store.lastAuthError?.kind, .noInternet)
        XCTAssertFalse(store.lastAuthError!.shouldClearSession)
    }

    func testTimeoutAndUnreachableKeepToken() async {
        for kind: AuthErrorKind in [.timeout, .unreachable] {
            let tokens = InMemoryAuthTokenStore(defaults: defaults)
            tokens.saveToken("tok-\(kind)")
            let cache = UserDefaultsAuthUserCache(
                key: "cache.\(UUID().uuidString)",
                defaults: defaults
            )
            cache.saveUser(Self.sampleUser(status: .active))
            let remote = MockAuthRemote()
            remote.meResult = .failure(AuthAPIError(kind: kind, message: "netz"))
            let store = AuthSessionStore(tokenStore: tokens, userCache: cache, remote: remote)
            await store.bootstrap()
            XCTAssertEqual(store.token, "tok-\(kind)", "kind \(kind) should keep token")
            XCTAssertTrue(store.canUseApp)
        }
    }

    func testLogoutClearsKeychainAndState() async {
        let remote = MockAuthRemote()
        remote.loginResult = .success(Self.sampleResponse(status: .active))
        let tokens = InMemoryAuthTokenStore(defaults: defaults)
        let cache = UserDefaultsAuthUserCache(defaults: defaults)
        let store = AuthSessionStore(tokenStore: tokens, userCache: cache, remote: remote)

        await store.login(email: "user@example.com", password: "password1")
        XCTAssertNotNil(tokens.loadToken())
        XCTAssertNotNil(cache.loadUser())

        store.logout()

        XCTAssertNil(store.token)
        XCTAssertNil(store.user)
        XCTAssertNil(tokens.loadToken())
        XCTAssertNil(cache.loadUser())
        XCTAssertFalse(store.canCallServerAPIs)
        XCTAssertFalse(store.canUseLocalFeatures)
        XCTAssertFalse(store.isOfflineSession)
    }

    func testOfflineLocalAccessVsServerDenial() async {
        let tokens = InMemoryAuthTokenStore(defaults: defaults)
        tokens.saveToken("tok-offline")
        let cache = UserDefaultsAuthUserCache(defaults: defaults)
        cache.saveUser(Self.sampleUser(status: .active, role: .user))
        let remote = MockAuthRemote()
        remote.meResult = .failure(
            AuthAPIError(kind: .timeout, message: "Zeitüberschreitung")
        )
        let store = AuthSessionStore(tokenStore: tokens, userCache: cache, remote: remote)
        await store.bootstrap()

        // Local investigation allowed; server tier denied while offline.
        XCTAssertTrue(store.canUseLocalFeatures)
        XCTAssertTrue(store.hasBearerToken)
        XCTAssertFalse(store.canCallServerAPIs)
        XCTAssertEqual(store.accessTier, .localOnly)
        XCTAssertFalse(store.isAdmin)
        XCTAssertThrowsError(try store.requireServerAuth()) { err in
            XCTAssertEqual((err as? AuthAPIError)?.kind, .unreachable)
        }

        // After logout: no local or server access.
        store.logout()
        XCTAssertFalse(store.canUseLocalFeatures)
        XCTAssertThrowsError(try store.requireServerAuth()) { err in
            let auth = err as? AuthAPIError
            XCTAssertEqual(auth?.kind, .forbidden)
        }
    }

    func testAdminVsUserAccessFlags() async {
        let remote = MockAuthRemote()
        remote.loginResult = .success(
            AuthResponse(
                accessToken: "tok-admin",
                tokenType: "bearer",
                user: Self.sampleUser(status: .active, role: .admin)
            )
        )
        let store = makeStore(remote: remote)
        await store.login(email: "admin@example.com", password: "password1")
        XCTAssertTrue(store.isAdmin)
        XCTAssertTrue(store.requireAdmin())
        XCTAssertTrue(store.canUseLocalFeatures)

        store.logout()
        remote.loginResult = .success(Self.sampleResponse(status: .active))
        await store.login(email: "user@example.com", password: "password1")
        XCTAssertFalse(store.isAdmin)
        XCTAssertFalse(store.requireAdmin())
        XCTAssertTrue(store.canUseApp)
    }

    func testForbiddenClearsSessionOnBootstrap() async {
        let tokens = InMemoryAuthTokenStore(defaults: defaults)
        tokens.saveToken("tok-forbid")
        let cache = UserDefaultsAuthUserCache(defaults: defaults)
        cache.saveUser(Self.sampleUser(status: .active))
        let remote = MockAuthRemote()
        remote.meResult = .failure(
            AuthAPIError(kind: .forbidden, message: "Keine Berechtigung", statusCode: 403)
        )
        let store = AuthSessionStore(tokenStore: tokens, userCache: cache, remote: remote)
        await store.bootstrap()
        XCTAssertNil(store.token)
        XCTAssertFalse(store.canUseApp)
    }

    func testLegacyUserDefaultsTokenMigratesOnce() {
        let legacyKey = AuthTokenKeychainStore.legacyUserDefaultsKey
        defaults.set("legacy-jwt", forKey: legacyKey)
        let store = InMemoryAuthTokenStore(legacyKey: legacyKey, defaults: defaults)

        XCTAssertEqual(store.loadToken(), "legacy-jwt")
        XCTAssertNil(defaults.string(forKey: legacyKey))
        XCTAssertEqual(store.loadToken(), "legacy-jwt")
    }

    // MARK: - Helpers

    private func makeStore(remote: MockAuthRemote) -> AuthSessionStore {
        AuthSessionStore(
            tokenStore: InMemoryAuthTokenStore(defaults: defaults),
            userCache: UserDefaultsAuthUserCache(
                key: "user.\(UUID().uuidString)",
                defaults: defaults
            ),
            remote: remote
        )
    }

    private static func sampleUser(
        status: AuthUserStatus,
        role: AuthUserRole = .user,
        email: String = "user@example.com"
    ) -> AuthUser {
        AuthUser(
            id: "u1",
            email: email,
            displayName: "Test",
            role: role,
            status: status,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            approvedAt: status == .active ? "2026-01-02T00:00:00Z" : nil
        )
    }

    private static func sampleResponse(status: AuthUserStatus) -> AuthResponse {
        AuthResponse(
            accessToken: "tok-live",
            tokenType: "bearer",
            user: sampleUser(status: status)
        )
    }
}

final class MockAuthRemote: AuthRemoteClient, @unchecked Sendable {
    var loginResult: Result<AuthResponse, Error> = .failure(AuthAPIError(message: "unset"))
    var registerResult: Result<AuthResponse, Error> = .failure(AuthAPIError(message: "unset"))
    var meResult: Result<AuthUser, Error> = .failure(AuthAPIError(message: "unset"))
    var changePasswordError: Error?

    func register(email: String, password: String, displayName: String?) async throws -> AuthResponse {
        try registerResult.get()
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try loginResult.get()
    }

    func me(token: String) async throws -> AuthUser {
        try meResult.get()
    }

    func changePassword(current: String, new: String, token: String) async throws {
        if let changePasswordError { throw changePasswordError }
    }
}
