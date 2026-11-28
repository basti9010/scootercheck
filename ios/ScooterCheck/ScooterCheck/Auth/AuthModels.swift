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

/// Stable server `code` values from scootercheck-auth (`backend/app/errors.py`).
/// Prefer these over German `detail` string matching when present.
enum AuthErrorCode {
    static let invalidCredentials = "invalid_credentials"
    static let notAuthenticated = "not_authenticated"
    static let tokenInvalid = "token_invalid"
    static let tokenExpired = "token_expired"
    static let userUnknown = "user_unknown"
    static let forbidden = "forbidden"
    static let accountNotActive = "account_not_active"
    static let emailTaken = "email_taken"
    static let domainNotAllowed = "domain_not_allowed"
    static let registrationLocked = "registration_locked"
    static let validationError = "validation_error"
    static let serverError = "server_error"
}

/// Client-side auth failure taxonomy (login, bootstrap, admin, server APIs).
enum AuthErrorKind: Equatable, Sendable {
    case noInternet
    case unreachable
    case timeout
    case invalidCredentials
    case expired
    case revoked
    case forbidden
    case serverError(statusCode: Int)
    case unknown

    /// Bootstrap / `/auth/me`: only these clear the local session.
    var shouldClearSession: Bool {
        switch self {
        case .invalidCredentials, .expired, .revoked, .forbidden:
            return true
        case .noInternet, .unreachable, .timeout, .serverError, .unknown:
            return false
        }
    }

    var isTransientNetworkFailure: Bool {
        switch self {
        case .noInternet, .unreachable, .timeout:
            return true
        default:
            return false
        }
    }
}

struct AuthAPIError: LocalizedError, Equatable {
    let kind: AuthErrorKind
    let message: String
    /// HTTP status when known (login 401, me 403, 5xx, …).
    let statusCode: Int?

    var errorDescription: String? { message }

    init(kind: AuthErrorKind, message: String, statusCode: Int? = nil) {
        self.kind = kind
        self.message = message
        self.statusCode = statusCode
    }

    /// Backward-compatible convenience used by older call sites.
    init(message: String) {
        self.kind = .unknown
        self.message = message
        self.statusCode = nil
    }

    var shouldClearSession: Bool { kind.shouldClearSession }
    var isTransientNetworkFailure: Bool { kind.isTransientNetworkFailure }
}

/// Maps URL / HTTP failures into `AuthAPIError` with a stable taxonomy.
enum AuthErrorMapper {
    static func mapURLFailure(_ error: Error) -> AuthAPIError {
        if let urlError = error as? URLError {
            return mapURLError(urlError)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: ns.code)
            return mapURLError(URLError(code))
        }
        return AuthAPIError(kind: .unknown, message: error.localizedDescription)
    }

    static func mapURLError(_ error: URLError) -> AuthAPIError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return AuthAPIError(
                kind: .noInternet,
                message: "Keine Internetverbindung — lokale Daten bleiben verfügbar."
            )
        case .timedOut:
            return AuthAPIError(
                kind: .timeout,
                message: "Zeitüberschreitung — Server nicht rechtzeitig erreichbar."
            )
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .networkConnectionLost, .internationalRoamingOff:
            return AuthAPIError(
                kind: .unreachable,
                message: "Server nicht erreichbar — bitte später erneut versuchen."
            )
        default:
            return AuthAPIError(
                kind: .unreachable,
                message: error.localizedDescription
            )
        }
    }

    static func mapHTTP(statusCode: Int, detail: String?, code: String? = nil) -> AuthAPIError {
        let raw = (detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let serverCode = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer stable server codes (Agent B) over German detail heuristics.
        if !serverCode.isEmpty {
            switch serverCode {
            case AuthErrorCode.invalidCredentials:
                return AuthAPIError(
                    kind: .invalidCredentials,
                    message: raw.isEmpty ? "E-Mail oder Passwort falsch" : raw,
                    statusCode: statusCode
                )
            case AuthErrorCode.tokenExpired:
                return AuthAPIError(
                    kind: .expired,
                    message: raw.isEmpty ? "Sitzung abgelaufen — bitte erneut anmelden." : raw,
                    statusCode: statusCode
                )
            case AuthErrorCode.tokenInvalid, AuthErrorCode.userUnknown, AuthErrorCode.notAuthenticated:
                return AuthAPIError(
                    kind: .expired,
                    message: raw.isEmpty ? "Anmeldung ungültig — bitte erneut anmelden." : raw,
                    statusCode: statusCode
                )
            case AuthErrorCode.forbidden, AuthErrorCode.accountNotActive,
                 AuthErrorCode.domainNotAllowed, AuthErrorCode.registrationLocked:
                return AuthAPIError(
                    kind: .forbidden,
                    message: raw.isEmpty ? "Keine Berechtigung." : raw,
                    statusCode: statusCode
                )
            case AuthErrorCode.serverError:
                return AuthAPIError(
                    kind: .serverError(statusCode: statusCode),
                    message: raw.isEmpty ? "Serverfehler (\(statusCode))" : raw,
                    statusCode: statusCode
                )
            default:
                break
            }
        }

        switch statusCode {
        case 401:
            if lower.contains("revok") || lower.contains("widerruf") {
                return AuthAPIError(
                    kind: .revoked,
                    message: raw.isEmpty ? "Sitzung widerrufen — bitte erneut anmelden." : raw,
                    statusCode: statusCode
                )
            }
            if lower.contains("expir") || lower.contains("abgelaufen") {
                return AuthAPIError(
                    kind: .expired,
                    message: raw.isEmpty ? "Sitzung abgelaufen — bitte erneut anmelden." : raw,
                    statusCode: statusCode
                )
            }
            if lower.contains("e-mail oder passwort")
                || lower.contains("passwort falsch")
                || lower.contains("invalid")
                || lower.contains("unauthorized")
                || raw.isEmpty {
                return AuthAPIError(
                    kind: .invalidCredentials,
                    message: raw.isEmpty ? "E-Mail oder Passwort falsch" : raw,
                    statusCode: statusCode
                )
            }
            return AuthAPIError(
                kind: .expired,
                message: raw.isEmpty ? "Anmeldung ungültig — bitte erneut anmelden." : raw,
                statusCode: statusCode
            )
        case 403:
            if lower.contains("revok") || lower.contains("widerruf") {
                return AuthAPIError(
                    kind: .revoked,
                    message: raw.isEmpty ? "Zugang widerrufen." : raw,
                    statusCode: statusCode
                )
            }
            return AuthAPIError(
                kind: .forbidden,
                message: raw.isEmpty ? "Keine Berechtigung." : raw,
                statusCode: statusCode
            )
        case 408, 504:
            return AuthAPIError(
                kind: .timeout,
                message: raw.isEmpty ? "Zeitüberschreitung am Server." : raw,
                statusCode: statusCode
            )
        case 502, 503:
            return AuthAPIError(
                kind: .unreachable,
                message: raw.isEmpty ? "Server kurz nicht erreichbar." : raw,
                statusCode: statusCode
            )
        case 500...599:
            return AuthAPIError(
                kind: .serverError(statusCode: statusCode),
                message: raw.isEmpty ? "Serverfehler (\(statusCode))" : raw,
                statusCode: statusCode
            )
        default:
            return AuthAPIError(
                kind: .unknown,
                message: raw.isEmpty ? "Fehler \(statusCode)" : raw,
                statusCode: statusCode
            )
        }
    }
}
