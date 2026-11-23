import Foundation
import SwiftUI

// MARK: - Grade vocabulary (Cycle 11)

/// Epistemic grades for server diagnostics.
/// CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN.
/// Flags alone never equal VERIFIED / END_TO_END_VERIFIED.
enum FirmwareDiagnosticsGrade: String, Equatable, Codable, Sendable, CaseIterable {
    case configured = "CONFIGURED"
    case available = "AVAILABLE"
    case verified = "VERIFIED"
    case endToEndVerified = "END_TO_END_VERIFIED"
    case failed = "FAILED"
    case unknown = "UNKNOWN"
    case notConfigured = "NOT_CONFIGURED"
    case routeMissing = "ROUTE_MISSING"

    /// Parse wire / JSON strings; unknown tokens → `.unknown`.
    static func parse(_ raw: String?) -> FirmwareDiagnosticsGrade {
        guard let raw else { return .unknown }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch t {
        case "CONFIGURED": return .configured
        case "AVAILABLE": return .available
        case "VERIFIED": return .verified
        case "END_TO_END_VERIFIED", "E2E_VERIFIED", "ENDTOENDVERIFIED":
            return .endToEndVerified
        case "FAILED", "ERROR", "FAIL": return .failed
        case "NOT_CONFIGURED", "NOTCONFIGURED", "UNCONFIGURED":
            return .notConfigured
        case "ROUTE_MISSING", "ROUTEMISSING", "NOT_FOUND", "404":
            return .routeMissing
        case "UNKNOWN", "": return .unknown
        default: return .unknown
        }
    }

    var token: String { rawValue }

    var labelDE: String {
        switch self {
        case .configured: return "Konfiguriert"
        case .available: return "Erreichbar"
        case .verified: return "Verifiziert"
        case .endToEndVerified: return "E2E verifiziert"
        case .failed: return "Fehlgeschlagen"
        case .unknown: return "Unbekannt"
        case .notConfigured: return "Nicht konfiguriert"
        case .routeMissing: return "API noch nicht verfügbar"
        }
    }

    /// UI color for status badges (Theme-aligned).
    var color: Color {
        switch self {
        case .endToEndVerified, .verified:
            return Theme.accent
        case .available:
            return Color(red: 0.45, green: 0.78, blue: 0.55)
        case .configured:
            return Theme.warn
        case .failed:
            return Theme.danger
        case .notConfigured, .routeMissing:
            return Theme.hintOrange
        case .unknown:
            return Theme.textMuted
        }
    }
}

/// Named diagnostic subsystems shown in Serverdiagnose.
enum FirmwareDiagnosticsComponent: String, Equatable, Codable, Sendable, CaseIterable, Identifiable {
    case server
    case tea
    case ghidra
    case worker

    var id: String { rawValue }

    var labelDE: String {
        switch self {
        case .server: return "Server"
        case .tea: return "TEA"
        case .ghidra: return "Ghidra"
        case .worker: return "Worker"
        }
    }
}

struct FirmwareDiagnosticsComponentStatus: Equatable, Codable, Sendable, Identifiable {
    var id: String { component.rawValue }
    var component: FirmwareDiagnosticsComponent
    var grade: FirmwareDiagnosticsGrade
    var detail: String?

    enum CodingKeys: String, CodingKey {
        case component, grade, detail, status, name
    }

    init(
        component: FirmwareDiagnosticsComponent,
        grade: FirmwareDiagnosticsGrade,
        detail: String? = nil
    ) {
        self.component = component
        self.grade = grade
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decodeIfPresent(String.self, forKey: .component)
            ?? c.decodeIfPresent(String.self, forKey: .name)
            ?? "server"
        let parsedComp = FirmwareDiagnosticsComponent(rawValue: name.lowercased())
            ?? Self.mapAlias(name)
        component = parsedComp
        let gradeRaw = try c.decodeIfPresent(String.self, forKey: .grade)
            ?? c.decodeIfPresent(String.self, forKey: .status)
        grade = FirmwareDiagnosticsGrade.parse(gradeRaw)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(component.rawValue, forKey: .component)
        try c.encode(grade.rawValue, forKey: .grade)
        try c.encodeIfPresent(detail, forKey: .detail)
    }

    private static func mapAlias(_ raw: String) -> FirmwareDiagnosticsComponent {
        let u = raw.lowercased()
        if u.contains("tea") || u.contains("decrypt") { return .tea }
        if u.contains("ghidra") { return .ghidra }
        if u.contains("worker") || u.contains("health") { return .worker }
        return .server
    }
}

/// Response from `GET /v1/diagnostics/status` (admin-preferred; 404 until PM wires).
struct FirmwareDiagnosticsStatus: Equatable, Codable, Sendable {
    var ok: Bool?
    var service: String?
    var checkedAt: Date?
    var components: [FirmwareDiagnosticsComponentStatus]
    var overallGrade: FirmwareDiagnosticsGrade?
    var message: String?
    var lastSelftestId: String?

    enum CodingKeys: String, CodingKey {
        case ok, service, checkedAt, components, overallGrade, message, lastSelftestId
        case tea, ghidra, worker, server
        case teaGrade, ghidraGrade, workerGrade, serverGrade
    }

    init(
        ok: Bool? = nil,
        service: String? = nil,
        checkedAt: Date? = nil,
        components: [FirmwareDiagnosticsComponentStatus] = [],
        overallGrade: FirmwareDiagnosticsGrade? = nil,
        message: String? = nil,
        lastSelftestId: String? = nil
    ) {
        self.ok = ok
        self.service = service
        self.checkedAt = checkedAt
        self.components = components
        self.overallGrade = overallGrade
        self.message = message
        self.lastSelftestId = lastSelftestId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
        service = try c.decodeIfPresent(String.self, forKey: .service)
        checkedAt = try c.decodeIfPresent(Date.self, forKey: .checkedAt)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        lastSelftestId = try c.decodeIfPresent(String.self, forKey: .lastSelftestId)
        if let g = try c.decodeIfPresent(String.self, forKey: .overallGrade) {
            overallGrade = FirmwareDiagnosticsGrade.parse(g)
        } else {
            overallGrade = nil
        }

        if let list = try c.decodeIfPresent([FirmwareDiagnosticsComponentStatus].self, forKey: .components),
           !list.isEmpty {
            components = list
        } else {
            // Flat grade fields (Agent A may propose either shape).
            var built: [FirmwareDiagnosticsComponentStatus] = []
            if let g = try c.decodeIfPresent(String.self, forKey: .serverGrade)
                ?? c.decodeIfPresent(String.self, forKey: .server) {
                built.append(.init(component: .server, grade: .parse(g)))
            }
            if let g = try c.decodeIfPresent(String.self, forKey: .teaGrade)
                ?? c.decodeIfPresent(String.self, forKey: .tea) {
                built.append(.init(component: .tea, grade: .parse(g)))
            }
            if let g = try c.decodeIfPresent(String.self, forKey: .ghidraGrade)
                ?? c.decodeIfPresent(String.self, forKey: .ghidra) {
                built.append(.init(component: .ghidra, grade: .parse(g)))
            }
            if let g = try c.decodeIfPresent(String.self, forKey: .workerGrade)
                ?? c.decodeIfPresent(String.self, forKey: .worker) {
                built.append(.init(component: .worker, grade: .parse(g)))
            }
            components = built
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(ok, forKey: .ok)
        try c.encodeIfPresent(service, forKey: .service)
        try c.encodeIfPresent(checkedAt, forKey: .checkedAt)
        try c.encode(components, forKey: .components)
        try c.encodeIfPresent(overallGrade?.rawValue, forKey: .overallGrade)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(lastSelftestId, forKey: .lastSelftestId)
    }

    func grade(for component: FirmwareDiagnosticsComponent) -> FirmwareDiagnosticsGrade {
        components.first(where: { $0.component == component })?.grade ?? .unknown
    }
}

/// Selftest job / summary from `/v1/diagnostics/selftest*`.
struct FirmwareDiagnosticsSelftest: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var state: String?
    var startedAt: Date?
    var finishedAt: Date?
    var overallGrade: FirmwareDiagnosticsGrade?
    var components: [FirmwareDiagnosticsComponentStatus]
    var message: String?
    var syntheticOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case id, selftestId, state, status, startedAt, finishedAt
        case overallGrade, components, message, syntheticOnly
    }

    init(
        id: String,
        state: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        overallGrade: FirmwareDiagnosticsGrade? = nil,
        components: [FirmwareDiagnosticsComponentStatus] = [],
        message: String? = nil,
        syntheticOnly: Bool? = true
    ) {
        self.id = id
        self.state = state
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.overallGrade = overallGrade
        self.components = components
        self.message = message
        self.syntheticOnly = syntheticOnly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .selftestId)
            ?? UUID().uuidString
        state = try c.decodeIfPresent(String.self, forKey: .state)
            ?? c.decodeIfPresent(String.self, forKey: .status)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        if let g = try c.decodeIfPresent(String.self, forKey: .overallGrade) {
            overallGrade = FirmwareDiagnosticsGrade.parse(g)
        } else {
            overallGrade = nil
        }
        components = try c.decodeIfPresent([FirmwareDiagnosticsComponentStatus].self, forKey: .components) ?? []
        message = try c.decodeIfPresent(String.self, forKey: .message)
        syntheticOnly = try c.decodeIfPresent(Bool.self, forKey: .syntheticOnly)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(state, forKey: .state)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try c.encodeIfPresent(overallGrade?.rawValue, forKey: .overallGrade)
        try c.encode(components, forKey: .components)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(syntheticOnly, forKey: .syntheticOnly)
    }
}

struct FirmwareDiagnosticsSelftestStartResponse: Equatable, Codable, Sendable {
    var selftest: FirmwareDiagnosticsSelftest?

    enum CodingKeys: String, CodingKey {
        case selftest, id, selftestId, state, message
    }

    init(selftest: FirmwareDiagnosticsSelftest?) {
        self.selftest = selftest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try c.decodeIfPresent(FirmwareDiagnosticsSelftest.self, forKey: .selftest) {
            selftest = nested
        } else if let id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .selftestId) {
            selftest = FirmwareDiagnosticsSelftest(
                id: id,
                state: try c.decodeIfPresent(String.self, forKey: .state),
                message: try c.decodeIfPresent(String.self, forKey: .message)
            )
        } else {
            selftest = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(selftest, forKey: .selftest)
    }
}

/// Stub export payload for share sheet (full report when PM wires `/v1/diagnostics/report`).
struct FirmwareDiagnosticsReportStub: Equatable, Codable, Sendable {
    var generatedAt: Date
    var status: FirmwareDiagnosticsStatus?
    var lastSelftest: FirmwareDiagnosticsSelftest?
    var note: String

    static func make(
        status: FirmwareDiagnosticsStatus?,
        lastSelftest: FirmwareDiagnosticsSelftest?,
        note: String = "Diagnosebericht (Stub) — voller Export folgt nach Server-Route."
    ) -> FirmwareDiagnosticsReportStub {
        FirmwareDiagnosticsReportStub(
            generatedAt: Date(),
            status: status,
            lastSelftest: lastSelftest,
            note: note
        )
    }
}

// MARK: - Mapping helpers (testable)

enum FirmwareDiagnosticsStatusMapper {
    /// Map public `/health` flags → component grades.
    /// Never promotes flag-only signals to VERIFIED / END_TO_END_VERIFIED.
    static func fromWorkerHealth(_ health: FirmwareWorkerHealth) -> FirmwareDiagnosticsStatus {
        var components: [FirmwareDiagnosticsComponentStatus] = []

        let serverGrade: FirmwareDiagnosticsGrade = health.ok ? .available : .failed
        components.append(.init(
            component: .server,
            grade: serverGrade,
            detail: health.service ?? "scootercheck-fw"
        ))

        let teaGrade: FirmwareDiagnosticsGrade = {
            guard let configured = health.decryptConfigured else { return .unknown }
            return configured ? .configured : .notConfigured
        }()
        components.append(.init(
            component: .tea,
            grade: teaGrade,
            detail: "decryptConfigured=\(health.decryptConfigured.map(String.init(describing:)) ?? "?") — flag ≠ VERIFIED"
        ))

        let ghidraGrade: FirmwareDiagnosticsGrade = {
            let configured = health.ghidraConfigured ?? false
            let enabled = health.ghidraEnabled ?? false
            if !configured { return .notConfigured }
            if configured && enabled { return .configured }
            return .configured
        }()
        components.append(.init(
            component: .ghidra,
            grade: ghidraGrade,
            detail: "ghidraConfigured=\(health.ghidraConfigured.map(String.init(describing:)) ?? "?"), enabled=\(health.ghidraEnabled.map(String.init(describing:)) ?? "?") — flag ≠ VERIFIED"
        ))

        let workerGrade: FirmwareDiagnosticsGrade = health.ok ? .available : .failed
        components.append(.init(
            component: .worker,
            grade: workerGrade,
            detail: "GET /health"
        ))

        let overall: FirmwareDiagnosticsGrade = {
            if components.contains(where: { $0.grade == .failed }) { return .failed }
            if components.allSatisfy({ $0.grade == .available || $0.grade == .configured }) {
                return .available
            }
            if components.contains(where: { $0.grade == .notConfigured }) { return .configured }
            return .unknown
        }()

        return FirmwareDiagnosticsStatus(
            ok: health.ok,
            service: health.service,
            checkedAt: Date(),
            components: components,
            overallGrade: overall,
            message: "Abgeleitet aus /health (keine Selftest-Verifikation)."
        )
    }

    /// Ensure UI always shows all four rows even if the API omits some.
    static func normalizedComponents(from status: FirmwareDiagnosticsStatus) -> [FirmwareDiagnosticsComponentStatus] {
        FirmwareDiagnosticsComponent.allCases.map { comp in
            status.components.first(where: { $0.component == comp })
                ?? FirmwareDiagnosticsComponentStatus(component: comp, grade: .unknown, detail: nil)
        }
    }
}
