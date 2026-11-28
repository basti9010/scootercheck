import XCTest
@testable import ScooterCheck

final class AuthErrorMapperTests: XCTestCase {
    func testNoInternet() {
        let err = AuthErrorMapper.mapURLError(URLError(.notConnectedToInternet))
        XCTAssertEqual(err.kind, .noInternet)
        XCTAssertTrue(err.isTransientNetworkFailure)
        XCTAssertFalse(err.shouldClearSession)
    }

    func testTimeout() {
        let err = AuthErrorMapper.mapURLError(URLError(.timedOut))
        XCTAssertEqual(err.kind, .timeout)
        XCTAssertFalse(err.shouldClearSession)
    }

    func testUnreachableHost() {
        let err = AuthErrorMapper.mapURLError(URLError(.cannotConnectToHost))
        XCTAssertEqual(err.kind, .unreachable)
        XCTAssertFalse(err.shouldClearSession)
    }

    func testInvalidCredentials() {
        let err = AuthErrorMapper.mapHTTP(statusCode: 401, detail: "E-Mail oder Passwort falsch")
        XCTAssertEqual(err.kind, .invalidCredentials)
        XCTAssertTrue(err.shouldClearSession)
    }

    func testExpired() {
        let err = AuthErrorMapper.mapHTTP(statusCode: 401, detail: "Token expired")
        XCTAssertEqual(err.kind, .expired)
        XCTAssertTrue(err.shouldClearSession)
    }

    func testRevoked() {
        let err = AuthErrorMapper.mapHTTP(statusCode: 401, detail: "token revoked")
        XCTAssertEqual(err.kind, .revoked)
        let err403 = AuthErrorMapper.mapHTTP(statusCode: 403, detail: "widerrufen")
        XCTAssertEqual(err403.kind, .revoked)
    }

    func testForbidden() {
        let err = AuthErrorMapper.mapHTTP(statusCode: 403, detail: "Admin only")
        XCTAssertEqual(err.kind, .forbidden)
        XCTAssertTrue(err.shouldClearSession)
    }

    func testServerError() {
        let err = AuthErrorMapper.mapHTTP(statusCode: 500, detail: nil)
        XCTAssertEqual(err.kind, .serverError(statusCode: 500))
        XCTAssertFalse(err.shouldClearSession)
    }

    func testBadGatewayMapsUnreachable() {
        let err = AuthErrorMapper.mapHTTP(statusCode: 502, detail: "Bad Gateway")
        XCTAssertEqual(err.kind, .unreachable)
        XCTAssertFalse(err.shouldClearSession)
    }

    func testWrongCredentialsHelperUsesKind() {
        let err = AuthAPIError(kind: .invalidCredentials, message: "x", statusCode: 401)
        XCTAssertTrue(AuthCredentialsNormalizer.isWrongCredentials(err))
        XCTAssertFalse(
            AuthCredentialsNormalizer.isWrongCredentials(
                AuthAPIError(kind: .timeout, message: "Zeitüberschreitung")
            )
        )
    }

    func testStableServerCodesPreferredOverDetailText() {
        let expired = AuthErrorMapper.mapHTTP(
            statusCode: 401,
            detail: "something else",
            code: AuthErrorCode.tokenExpired
        )
        XCTAssertEqual(expired.kind, .expired)
        XCTAssertTrue(expired.shouldClearSession)

        let inactive = AuthErrorMapper.mapHTTP(
            statusCode: 403,
            detail: "Konto nicht freigeschaltet",
            code: AuthErrorCode.accountNotActive
        )
        XCTAssertEqual(inactive.kind, .forbidden)
        XCTAssertTrue(inactive.shouldClearSession)

        let invalid = AuthErrorMapper.mapHTTP(
            statusCode: 401,
            detail: nil,
            code: AuthErrorCode.invalidCredentials
        )
        XCTAssertEqual(invalid.kind, .invalidCredentials)
    }
}
