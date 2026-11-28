import Foundation

/// Pure access-tier decisions (local vs server vs admin).
/// Session clear/keep taxonomy lives on `AuthErrorKind` / `AuthErrorMapper` (Agent A/B).
enum AuthSessionPolicy {
    /// Outcome of a failed `/auth/me` during bootstrap / refresh.
    enum BootstrapFailureAction: Equatable {
        case clearSession
        case keepSession
    }

    /// Coarse access tiers used to separate local vs server vs admin work offline.
    enum AccessTier: Equatable {
        case signedOut
        /// Cached / restored active profile may use on-device features only.
        case localOnly
        /// Active user with a live (or assumed-valid) session for server APIs.
        case serverAPI
        /// Active admin — server admin routes (always require network + server checks).
        case adminAPI
    }

    /// Bridge to `AuthErrorKind.shouldClearSession` for call sites / tests.
    static func bootstrapFailureAction(kind: AuthErrorKind) -> BootstrapFailureAction {
        kind.shouldClearSession ? .clearSession : .keepSession
    }

    /// HTTP-status helper when only a status code is known (no stable `code` yet).
    static func bootstrapFailureAction(
        httpStatus: Int?,
        isTransportFailure: Bool
    ) -> BootstrapFailureAction {
        if isTransportFailure { return .keepSession }
        guard let httpStatus else { return .keepSession }
        return bootstrapFailureAction(kind: AuthErrorMapper.mapHTTP(statusCode: httpStatus, detail: nil).kind)
    }

    /// Resolve access tier from session bits (token present, user profile, network).
    static func accessTier(
        hasToken: Bool,
        user: AuthUser?,
        serverReachable: Bool
    ) -> AccessTier {
        guard hasToken, let user else { return .signedOut }
        guard user.isActive else { return .signedOut }
        if user.isAdmin, serverReachable { return .adminAPI }
        if serverReachable { return .serverAPI }
        return .localOnly
    }

    static func allowsLocalFeatures(_ tier: AccessTier) -> Bool {
        switch tier {
        case .localOnly, .serverAPI, .adminAPI: return true
        case .signedOut: return false
        }
    }

    static func allowsServerAPI(_ tier: AccessTier) -> Bool {
        switch tier {
        case .serverAPI, .adminAPI: return true
        case .signedOut, .localOnly: return false
        }
    }

    static func allowsAdminAPI(_ tier: AccessTier) -> Bool {
        tier == .adminAPI
    }
}
