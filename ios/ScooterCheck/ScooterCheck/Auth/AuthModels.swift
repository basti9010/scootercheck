import Foundation

enum AuthUserStatus: String, Codable, Sendable {
    case pending
    case active
    case rejected
    case disabled
}

enum AuthUserRole: String, Codable, Sendable {
    case user
    case admin
}

struct AuthUser: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let email: String
    let displayName: String?
    let role: AuthUserRole
    let status: AuthUserStatus
    let createdAt: String
    let updatedAt: String
    let approvedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, role, status
        case displayName = "display_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case approvedAt = "approved_at"
    }

    var isAdmin: Bool { role == .admin }
    var isActive: Bool { status == .active }
}

struct AuthResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}

struct AuthUsersList: Codable, Sendable {
    let users: [AuthUser]
}

struct AuthDomain: Codable, Equatable, Identifiable, Sendable {
    var id: String { domain }
    let domain: String
    let createdAt: String
    let createdBy: String?

    enum CodingKeys: String, CodingKey {
        case domain
        case createdAt = "created_at"
        case createdBy = "created_by"
    }
}

struct AuthDomainsList: Codable, Sendable {
    let domains: [AuthDomain]
}

struct AuthPasswordResetResult: Codable, Sendable {
    let message: String
    let temporaryPassword: String?
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case message, user
        case temporaryPassword = "temporary_password"
    }
}

struct AuthAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
