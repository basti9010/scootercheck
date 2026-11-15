import Foundation

/// Vertrag für optionalen Server: Decrypt → Ghidra → deterministischer Extract → optionale schema-KI.
/// Die App bleibt offline-fähig; ohne Base-URL: `notConfigured`.
protocol FirmwareServerAnalysisClienting: Sendable {
    var isConfigured: Bool { get }
    func submit(_ request: FirmwareAnalysisJobRequest, archiveData: Data) async throws -> FirmwareAnalysisJobStatus
    func poll(jobId: String) async throws -> FirmwareAnalysisJobStatus
}

/// Platzhalter-Client — später HTTP gegen euren Server; gleiche Job-/Result-Typen.
struct FirmwareServerAnalysisClient: FirmwareServerAnalysisClienting {
    /// Optional: z. B. aus Einstellungen / Managed Config.
    var baseURL: URL?

    var isConfigured: Bool { baseURL != nil }

    func submit(_ request: FirmwareAnalysisJobRequest, archiveData: Data) async throws -> FirmwareAnalysisJobStatus {
        _ = archiveData
        guard isConfigured else {
            return FirmwareAnalysisJobStatus(
                jobId: "",
                state: .notConfigured,
                progressPercent: 0,
                message: "Kein Analyse-Server konfiguriert — lokal Katalog/Deterministik nutzen.",
                result: nil,
                errorCode: "SERVER_NOT_CONFIGURED"
            )
        }
        // HTTP-Upload folgt in einem späteren Schritt (Auth, TLS, Retention).
        return FirmwareAnalysisJobStatus(
            jobId: UUID().uuidString,
            state: .queued,
            progressPercent: 0,
            message: "Job angelegt (Transport noch nicht implementiert).",
            result: nil,
            errorCode: "TRANSPORT_PENDING"
        )
    }

    func poll(jobId: String) async throws -> FirmwareAnalysisJobStatus {
        guard isConfigured else {
            return FirmwareAnalysisJobStatus(
                jobId: jobId,
                state: .notConfigured,
                progressPercent: 0,
                message: "Kein Analyse-Server konfiguriert.",
                result: nil,
                errorCode: "SERVER_NOT_CONFIGURED"
            )
        }
        return FirmwareAnalysisJobStatus(
            jobId: jobId,
            state: .failed,
            progressPercent: 0,
            message: "Polling noch nicht implementiert.",
            result: nil,
            errorCode: "TRANSPORT_PENDING"
        )
    }
}
