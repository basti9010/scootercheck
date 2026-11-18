import Foundation

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
            throw AuthAPIError(message: "Ungültige API-URL")
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
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AuthAPIError(message: "Keine HTTP-Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthAPIError(message: parseError(data) ?? "Fehler \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func parseError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let detail = obj["detail"] as? String { return detail }
        if let detail = obj["detail"] as? [[String: Any]],
           let msg = detail.first?["msg"] as? String {
            return msg
        }
        return nil
    }
}
