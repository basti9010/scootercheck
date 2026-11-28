import Foundation

/// Injectable surface for `AuthSessionStore` unit tests.
protocol AuthRemoteClient: Sendable {
    func register(email: String, password: String, displayName: String?) async throws -> AuthResponse
    func login(email: String, password: String) async throws -> AuthResponse
    func me(token: String) async throws -> AuthUser
    func changePassword(current: String, new: String, token: String) async throws
}

/// ScooterCheck Auth API (Hetzner hinter nginx).
enum AuthAPIClient {
    /// HTTPS über bestehende API-Domain; Pfad getrennt von TuningScanner.
    static let baseURLString = "https://api.tuningscanner.de/scootercheck"

    static func register(email: String, password: String, displayName: String?) async throws -> AuthResponse {
        var body: [String: Any] = [
            "email": email,
            "password": password,
        ]
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["display_name"] = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try await request(path: "/auth/register", method: "POST", body: body)
    }

    static func login(email: String, password: String) async throws -> AuthResponse {
        try await request(
            path: "/auth/login",
            method: "POST",
            body: ["email": email, "password": password]
        )
    }

    static func me(token: String) async throws -> AuthUser {
        try await request(path: "/auth/me", method: "GET", token: token)
    }

    static func changePassword(current: String, new: String, token: String) async throws {
        struct Msg: Decodable { let message: String }
        let _: Msg = try await request(
            path: "/auth/change-password",
            method: "POST",
            body: [
                "current_password": current,
                "new_password": new,
            ],
            token: token
        )
    }

    static func resetPassword(userId: String, token: String, newPassword: String? = nil) async throws -> AuthPasswordResetResult {
        var body: [String: Any] = [:]
        if let newPassword {
            body["new_password"] = newPassword
        }
        return try await request(
            path: "/admin/users/\(userId)/reset-password",
            method: "POST",
            body: body.isEmpty ? [:] : body,
            token: token
        )
    }

    static func makeAdmin(userId: String, token: String) async throws -> AuthUser {
        try await request(path: "/admin/users/\(userId)/make-admin", method: "POST", token: token)
    }

    static func listUsers(token: String, status: AuthUserStatus? = nil) async throws -> [AuthUser] {
        var path = "/admin/users"
        if let status {
            path += "?status_filter=\(status.rawValue)"
        }
        let list: AuthUsersList = try await request(path: path, method: "GET", token: token)
        return list.users
    }

    static func approve(userId: String, token: String) async throws -> AuthUser {
        try await request(path: "/admin/users/\(userId)/approve", method: "POST", token: token)
    }

    static func reject(userId: String, token: String) async throws -> AuthUser {
        try await request(path: "/admin/users/\(userId)/reject", method: "POST", token: token)
    }

    static func disable(userId: String, token: String) async throws -> AuthUser {
        try await request(path: "/admin/users/\(userId)/disable", method: "POST", token: token)
    }

    static func enable(userId: String, token: String) async throws -> AuthUser {
        try await request(path: "/admin/users/\(userId)/enable", method: "POST", token: token)
    }

    static func updateUser(
        userId: String,
        token: String,
        displayName: String? = nil,
        role: AuthUserRole? = nil,
        status: AuthUserStatus? = nil,
        email: String? = nil
    ) async throws -> AuthUser {
        var body: [String: Any] = [:]
        if let displayName { body["display_name"] = displayName }
        if let role { body["role"] = role.rawValue }
        if let status { body["status"] = status.rawValue }
        if let email { body["email"] = email }
        return try await request(
            path: "/admin/users/\(userId)",
            method: "PATCH",
            body: body,
            token: token
        )
    }

    static func deleteUser(userId: String, token: String) async throws {
        struct Msg: Decodable { let message: String }
        let _: Msg = try await request(
            path: "/admin/users/\(userId)",
            method: "DELETE",
            token: token
        )
    }

    static func listDomains(token: String) async throws -> [AuthDomain] {
        let list: AuthDomainsList = try await request(path: "/admin/domains", method: "GET", token: token)
        return list.domains
    }

    static func addDomain(_ domain: String, token: String) async throws -> AuthDomain {
        try await request(
            path: "/admin/domains",
            method: "POST",
            body: ["domain": domain],
            token: token
        )
    }

    static func removeDomain(_ domain: String, token: String) async throws {
        struct Msg: Decodable { let message: String }
        let _: Msg = try await request(
            path: "/admin/domains/\(domain)",
            method: "DELETE",
            token: token
        )
    }

    private static func request<T: Decodable>(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURLString + path) else {
            throw AuthAPIError(kind: .unknown, message: "Ungültige API-URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AuthErrorMapper.mapURLFailure(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthAPIError(kind: .unreachable, message: "Keine HTTP-Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = parseErrorPayload(data)
            throw AuthErrorMapper.mapHTTP(
                statusCode: http.statusCode,
                detail: parsed.detail,
                code: parsed.code
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AuthAPIError(
                kind: .serverError(statusCode: http.statusCode),
                message: "Antwort nicht lesbar",
                statusCode: http.statusCode
            )
        }
    }

    /// Extracts FastAPI `detail` (string or validation array) and optional `code`.
    private static func parseErrorPayload(_ data: Data) -> (detail: String?, code: String?) {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let code = obj["code"] as? String
            if let detail = obj["detail"] as? String {
                return (detail, code)
            }
            if let detail = obj["detail"] as? [[String: Any]],
               let msg = detail.first?["msg"] as? String {
                return (msg, code ?? AuthErrorCode.validationError)
            }
            if code != nil {
                return (nil, code)
            }
        }
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return (nil, nil) }
        let lower = raw.lowercased()
        if lower.contains("<html") || lower.contains("<!doctype") {
            if lower.contains("502") || lower.contains("bad gateway") {
                return ("Bad Gateway — Server kurz nicht erreichbar", AuthErrorCode.serverError)
            }
            if lower.contains("503") {
                return ("Service kurz nicht verfügbar", AuthErrorCode.serverError)
            }
            return ("Unerwartete Antwort vom Server", nil)
        }
        if raw.count > 200 { return (String(raw.prefix(200)) + "…", nil) }
        return (raw, nil)
    }
}

/// Live adapter so `AuthSessionStore` can depend on `AuthRemoteClient`.
struct LiveAuthRemoteClient: AuthRemoteClient {
    func register(email: String, password: String, displayName: String?) async throws -> AuthResponse {
        try await AuthAPIClient.register(email: email, password: password, displayName: displayName)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await AuthAPIClient.login(email: email, password: password)
    }

    func me(token: String) async throws -> AuthUser {
        try await AuthAPIClient.me(token: token)
    }

    func changePassword(current: String, new: String, token: String) async throws {
        try await AuthAPIClient.changePassword(current: current, new: new, token: token)
    }
}
