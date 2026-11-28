import XCTest
@testable import ScooterCheck

final class AuthModelsTests: XCTestCase {
    private func makeUser(role: AuthUserRole, status: AuthUserStatus) -> AuthUser {
        AuthUser(
            id: "id-\(role.rawValue)-\(status.rawValue)",
            email: "\(role.rawValue)@example.com",
            displayName: nil,
            role: role,
            status: status,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            approvedAt: nil
        )
    }

    func testCanUseAppRequiresActiveStatus() {
        XCTAssertTrue(makeUser(role: .user, status: .active).isActive)
        XCTAssertFalse(makeUser(role: .user, status: .pending).isActive)
        XCTAssertFalse(makeUser(role: .user, status: .rejected).isActive)
        XCTAssertFalse(makeUser(role: .user, status: .disabled).isActive)
        // Admin role alone does not unlock the app without active status.
        XCTAssertFalse(makeUser(role: .admin, status: .pending).isActive)
        XCTAssertTrue(makeUser(role: .admin, status: .active).isActive)
    }

    func testIsAdminRoleSeparation() {
        XCTAssertTrue(makeUser(role: .admin, status: .active).isAdmin)
        XCTAssertFalse(makeUser(role: .user, status: .active).isAdmin)
    }

    func testAuthResponseCodingKeysRoundTrip() throws {
        let json = """
        {
          "access_token": "tok-abc",
          "token_type": "bearer",
          "user": {
            "id": "u1",
            "email": "a@b.de",
            "display_name": "A",
            "role": "user",
            "status": "active",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
            "approved_at": "2026-01-02T00:00:00Z"
          }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(decoded.accessToken, "tok-abc")
        XCTAssertEqual(decoded.tokenType, "bearer")
        XCTAssertEqual(decoded.user.email, "a@b.de")
        XCTAssertTrue(decoded.user.isActive)
        XCTAssertFalse(decoded.user.isAdmin)
    }
}
