import Foundation

/// Vertrag für optionalen Server: Decrypt → Extract → Deep-Analysis-JSON.
/// Die App bleibt offline-fähig; ohne Base-URL: `notConfigured`.
protocol FirmwareServerAnalysisClienting: Sendable {
    var isConfigured: Bool { get }
    func submit(_ request: FirmwareAnalysisJobRequest, archiveData: Data) async throws -> FirmwareAnalysisJobStatus
    func poll(jobId: String) async throws -> FirmwareAnalysisJobStatus
}

enum FirmwareServerAnalysisError: Error, LocalizedError {
    case notConfigured
    case badURL
    case httpStatus(Int, String)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Kein Analyse-Server konfiguriert."
        case .badURL: return "Ungültige Server-URL."
        case .httpStatus(let c, let b): return "Server-Fehler \(c): \(b)"
        case .decode(let e): return "Antwort nicht lesbar: \(e.localizedDescription)"
        }
    }
}

/// HTTP-Client gegen `server/firmware-analysis` (Upload → DECRYPT_CMD auf dem Server → JSON).
struct FirmwareServerAnalysisClient: FirmwareServerAnalysisClienting {
    /// Production default on api.tuningscanner.de (nginx → scootercheck-fw).
    static let defaultBaseURLString = "https://api.tuningscanner.de/scootercheck-fw"

    var baseURL: URL?
    var apiToken: String?
    /// ScooterCheck-Login JWT — Server akzeptiert `Authorization: Bearer` für active Users.
    var bearerToken: String?

    init(baseURL: URL? = nil, apiToken: String? = nil, bearerToken: String? = nil) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.bearerToken = bearerToken
    }

    /// Liest URL/Token aus AppSettings + Auth-Session (MainActor-Snapshot).
    @MainActor
    static func fromAppSettings() -> FirmwareServerAnalysisClient {
        let s = AppSettings.shared
        let configured = s.firmwareAnalysisServerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = configured.isEmpty ? Self.defaultBaseURLString : configured
        return FirmwareServerAnalysisClient(
            baseURL: URL(string: urlString),
            apiToken: {
                let t = s.firmwareAnalysisAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }(),
            bearerToken: AuthSessionStore.shared.token
        )
    }

    var isConfigured: Bool {
        guard let baseURL else { return false }
        return !(baseURL.scheme?.isEmpty ?? true) && !(baseURL.host?.isEmpty ?? true)
    }

    func submit(_ request: FirmwareAnalysisJobRequest, archiveData: Data) async throws -> FirmwareAnalysisJobStatus {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        let endpoint = baseURL.appendingPathComponent("v1/firmware/jobs")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        // Job läuft asynchron auf dem Server; POST speichert nur den Upload.
        req.timeoutInterval = 120
        applyAuth(&req)

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metaData = try JSONEncoder().encode(request)
        var body = Data()
        body.append(multipartField(name: "meta_json", value: String(data: metaData, encoding: .utf8) ?? "{}", boundary: boundary))
        body.append(multipartFile(
            name: "archive",
            filename: request.originalFileName.isEmpty ? "upload.bin" : request.originalFileName,
            mime: "application/octet-stream",
            fileData: archiveData,
            boundary: boundary
        ))
        body.append(Data("--\(boundary)--\r\n".utf8))
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        return try decodeStatus(data)
    }

    func poll(jobId: String) async throws -> FirmwareAnalysisJobStatus {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        let endpoint = baseURL
            .appendingPathComponent("v1/firmware/jobs")
            .appendingPathComponent(jobId)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        return try decodeStatus(data)
    }

    func adminListJobs(createdBy: String? = nil, limit: Int = 100) async throws -> FirmwareAdminJobsList {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        var comps = URLComponents(url: baseURL.appendingPathComponent("v1/firmware/admin/jobs"), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let createdBy, !createdBy.isEmpty {
            items.append(URLQueryItem(name: "created_by", value: createdBy))
        }
        comps?.queryItems = items
        guard let endpoint = comps?.url else { throw FirmwareServerAnalysisError.badURL }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        return try decode(FirmwareAdminJobsList.self, from: data)
    }

    func adminStats() async throws -> FirmwareAdminStats {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        let endpoint = baseURL.appendingPathComponent("v1/firmware/admin/stats")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        return try decode(FirmwareAdminStats.self, from: data)
    }

    func adminListStock() async throws -> FirmwareStockList {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        let endpoint = baseURL.appendingPathComponent("v1/firmware/admin/stock")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        return try decode(FirmwareStockList.self, from: data)
    }

    func adminDeleteStock(refId: String) async throws {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        let endpoint = baseURL
            .appendingPathComponent("v1/firmware/admin/stock")
            .appendingPathComponent(refId)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 60
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
    }

    func workerHealth() async throws -> FirmwareWorkerHealth {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        let endpoint = baseURL.appendingPathComponent("health")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        return try decode(FirmwareWorkerHealth.self, from: data)
    }

    func adminDeleteJob(jobId: String) async throws {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        let endpoint = baseURL
            .appendingPathComponent("v1/firmware/admin/jobs")
            .appendingPathComponent(jobId)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 60
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
    }

    func decompilePreview(jobId: String, maxChars: Int = 12_000) async throws -> FirmwareDecompilePreview {
        guard isConfigured, let baseURL else { throw FirmwareServerAnalysisError.notConfigured }
        var comps = URLComponents(
            url: baseURL
                .appendingPathComponent("v1/firmware/jobs")
                .appendingPathComponent(jobId)
                .appendingPathComponent("decompile"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [URLQueryItem(name: "preview_chars", value: String(maxChars))]
        guard let endpoint = comps?.url else { throw FirmwareServerAnalysisError.badURL }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(response, data: data)
        return try decode(FirmwareDecompilePreview.self, from: data)
    }

    // MARK: - Helpers

    private func applyAuth(_ req: inout URLRequest) {
        if let bearerToken, !bearerToken.isEmpty {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let apiToken, !apiToken.isEmpty {
            req.setValue(apiToken, forHTTPHeaderField: "X-ScooterCheck-Token")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FirmwareServerAnalysisError.httpStatus(http.statusCode, body)
        }
    }

    private func makeDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = ISO8601DateFormatter().date(from: s) { return d }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date \(s)")
        }
        return dec
    }

    private func decodeStatus(_ data: Data) throws -> FirmwareAnalysisJobStatus {
        try decode(FirmwareAnalysisJobStatus.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try makeDecoder().decode(type, from: data)
        } catch {
            throw FirmwareServerAnalysisError.decode(error)
        }
    }

    private func multipartField(name: String, value: String, boundary: String) -> Data {
        var d = Data()
        d.append(Data("--\(boundary)\r\n".utf8))
        d.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        d.append(Data("\(value)\r\n".utf8))
        return d
    }

    private func multipartFile(name: String, filename: String, mime: String, fileData: Data, boundary: String) -> Data {
        var d = Data()
        d.append(Data("--\(boundary)\r\n".utf8))
        d.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        d.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        d.append(fileData)
        d.append(Data("\r\n".utf8))
        return d
    }
}
