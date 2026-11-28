import XCTest
@testable import ScooterCheck

final class AuthSessionPolicyTests: XCTestCase {
    private func user(
        role: AuthUserRole = .user,
        status: AuthUserStatus = .active
    ) -> AuthUser {
        AuthUser(
            id: "u1",
            email: "user@example.com",
            displayName: "Test",
            role: role,
            status: status,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            approvedAt: status == .active ? "2026-01-01T00:00:00Z" : nil
        )
    }

    // MARK: - Bootstrap mirrors AuthErrorKind

    func testKindClearVsKeep() {
        XCTAssertEqual(AuthSessionPolicy.bootstrapFailureAction(kind: .expired), .clearSession)
        XCTAssertEqual(AuthSessionPolicy.bootstrapFailureAction(kind: .revoked), .clearSession)
        XCTAssertEqual(AuthSessionPolicy.bootstrapFailureAction(kind: .forbidden), .clearSession)
        XCTAssertEqual(AuthSessionPolicy.bootstrapFailureAction(kind: .invalidCredentials), .clearSession)
        XCTAssertEqual(AuthSessionPolicy.bootstrapFailureAction(kind: .noInternet), .keepSession)
        XCTAssertEqual(AuthSessionPolicy.bootstrapFailureAction(kind: .timeout), .keepSession)
        XCTAssertEqual(AuthSessionPolicy.bootstrapFailureAction(kind: .unreachable), .keepSession)
        XCTAssertEqual(
            AuthSessionPolicy.bootstrapFailureAction(kind: .serverError(statusCode: 500)),
            .keepSession
        )
    }

    func testHTTPStatusDelegation() {
        XCTAssertEqual(
            AuthSessionPolicy.bootstrapFailureAction(httpStatus: 401, isTransportFailure: false),
            .clearSession
        )
        XCTAssertEqual(
            AuthSessionPolicy.bootstrapFailureAction(httpStatus: 503, isTransportFailure: false),
            .keepSession
        )
        XCTAssertEqual(
            AuthSessionPolicy.bootstrapFailureAction(httpStatus: 401, isTransportFailure: true),
            .keepSession
        )
    }

    // MARK: - Offline local vs server vs admin

    func testSignedOutWhenNoToken() {
        let tier = AuthSessionPolicy.accessTier(hasToken: false, user: nil, serverReachable: true)
        XCTAssertEqual(tier, .signedOut)
        XCTAssertFalse(AuthSessionPolicy.allowsLocalFeatures(tier))
        XCTAssertFalse(AuthSessionPolicy.allowsServerAPI(tier))
        XCTAssertFalse(AuthSessionPolicy.allowsAdminAPI(tier))
    }

    func testPendingAndDisabledDenied() {
        XCTAssertEqual(
            AuthSessionPolicy.accessTier(hasToken: true, user: user(status: .pending), serverReachable: true),
            .signedOut
        )
        XCTAssertEqual(
            AuthSessionPolicy.accessTier(hasToken: true, user: user(status: .disabled), serverReachable: false),
            .signedOut
        )
    }

    func testActiveUserOfflineIsLocalOnly() {
        let tier = AuthSessionPolicy.accessTier(hasToken: true, user: user(), serverReachable: false)
        XCTAssertEqual(tier, .localOnly)
        XCTAssertTrue(AuthSessionPolicy.allowsLocalFeatures(tier))
        XCTAssertFalse(AuthSessionPolicy.allowsServerAPI(tier))
        XCTAssertFalse(AuthSessionPolicy.allowsAdminAPI(tier))
    }

    func testActiveUserOnlineGetsServerAPI() {
        let tier = AuthSessionPolicy.accessTier(hasToken: true, user: user(), serverReachable: true)
        XCTAssertEqual(tier, .serverAPI)
        XCTAssertTrue(AuthSessionPolicy.allowsServerAPI(tier))
        XCTAssertFalse(AuthSessionPolicy.allowsAdminAPI(tier))
    }

    func testAdminOnlineGetsAdminAPI() {
        let tier = AuthSessionPolicy.accessTier(
            hasToken: true,
            user: user(role: .admin),
            serverReachable: true
        )
        XCTAssertEqual(tier, .adminAPI)
        XCTAssertTrue(AuthSessionPolicy.allowsAdminAPI(tier))
    }

    func testAdminOfflineDoesNotElevateToAdminAPI() {
        let tier = AuthSessionPolicy.accessTier(
            hasToken: true,
            user: user(role: .admin),
            serverReachable: false
        )
        XCTAssertEqual(tier, .localOnly)
        XCTAssertFalse(AuthSessionPolicy.allowsAdminAPI(tier))
    }
}
