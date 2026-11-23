import Foundation

/// User-facing job / analysis status for Cycle-8 forensics UI.
/// Distinct from wire `FirmwareAnalysisJobState` so encrypted / non-analyzable
/// firmware is never presented as a successful decompile.
enum FirmwareAnalysisJobUIStatus: String, Equatable, Codable, Sendable, CaseIterable {
    case queued
    case processing
    case completed
    case failed
    case unsupported
    case incomplete

    /// Stable uppercase tokens for tests / logs / UI badges.
    var token: String {
        switch self {
        case .queued: return "QUEUED"
        case .processing: return "PROCESSING"
        case .completed: return "COMPLETED"
        case .failed: return "FAILED"
        case .unsupported: return "UNSUPPORTED"
        case .incomplete: return "INCOMPLETE"
        }
    }

    var labelDE: String {
        switch self {
        case .queued: return "Warteschlange"
        case .processing: return "In Bearbeitung"
        case .completed: return "Abgeschlossen"
        case .failed: return "Fehlgeschlagen"
        case .unsupported: return "Nicht unterstütztes Format"
        case .incomplete: return "Unvollständig (kein Klartext)"
        }
    }

    /// True only when the UI may claim a successful server/local deep analysis.
    var allowsSuccessfulDecompileClaim: Bool {
        self == .completed
    }
}

enum FirmwareAnalysisJobUIStatusMapper {
    /// Map wire job state → coarse UI status (crypto gate applied separately).
    static func fromJobState(_ state: FirmwareAnalysisJobState) -> FirmwareAnalysisJobUIStatus {
        switch state {
        case .queued:
            return .queued
        case .decrypting, .decompiling, .extracting, .llmEnrichment:
            return .processing
        case .completed:
            return .completed
        case .failed, .notConfigured:
            return .failed
        }
    }

    /// Completeness / container strings from server or local crypto gate.
    static func fromCompletenessHint(_ raw: String?) -> FirmwareAnalysisJobUIStatus? {
        guard let raw else { return nil }
        let u = raw.uppercased()
        if u.contains("ENCRYPTED_UNSUPPORTED")
            || u.contains("FORMAT_UNSUPPORTED")
            || u.contains("UNSUPPORTED") {
            return .unsupported
        }
        if u.contains("INCOMPLETE")
            || u.contains("ANALYSIS_NOT_POSSIBLE")
            || u.contains("PARTIAL_ANALYSIS")
            || u.contains("ENCRYPTED") {
            return .incomplete
        }
        return nil
    }

    /// Crypto gate: encrypted / unknown formats must not surface as COMPLETED decompile.
    static func applyCryptoGate(
        base: FirmwareAnalysisJobUIStatus,
        crypto: FirmwareCryptoAssessment,
        serverPlaintextAvailable: Bool,
        serverDecompileAvailable: Bool,
        completenessHint: String? = nil
    ) -> FirmwareAnalysisJobUIStatus {
        if let fromHint = fromCompletenessHint(completenessHint) {
            // Completeness overrides a false COMPLETED; leave in-flight states alone.
            if base == .completed || base == .failed {
                return fromHint
            }
        }

        switch base {
        case .queued, .processing, .failed:
            return base
        case .unsupported, .incomplete:
            return base
        case .completed:
            break
        }

        let encrypted = crypto.status == .confirmedByMetadata
            || crypto.status == .likelyByStructure
        if encrypted && !serverPlaintextAvailable {
            // Ciphertext without decrypt — never claim successful decompile.
            return .incomplete
        }
        if crypto.status == .unknownFormat && !serverPlaintextAvailable && !serverDecompileAvailable {
            return .unsupported
        }
        if encrypted && serverPlaintextAvailable && !serverDecompileAvailable {
            // Decrypt OK but deep/decompile not available → incomplete, not success.
            return .incomplete
        }
        return .completed
    }

    /// Convenience: map a polled job status + local crypto into the UI badge.
    static func resolve(
        job: FirmwareAnalysisJobStatus?,
        crypto: FirmwareCryptoAssessment,
        localOnlyFallback: FirmwareAnalysisJobUIStatus? = nil
    ) -> FirmwareAnalysisJobUIStatus {
        if let job {
            let base = fromJobState(job.state)
            let plain = job.plaintextSaved == true
                || !(job.plaintextSHA256?.isEmpty ?? true)
                || !(job.plaintextPath?.isEmpty ?? true)
            let decomp = job.decompileSaved == true
                || !(job.decompilePath?.isEmpty ?? true)
                || (job.result?.sources.contains(.serverDecompile) == true)
            let completeness = job.result?.analysisCompleteness
                ?? job.errorCode
            return applyCryptoGate(
                base: base,
                crypto: crypto,
                serverPlaintextAvailable: plain,
                serverDecompileAvailable: decomp,
                completenessHint: completeness
            )
        }
        if let localOnlyFallback {
            return applyCryptoGate(
                base: localOnlyFallback,
                crypto: crypto,
                serverPlaintextAvailable: false,
                serverDecompileAvailable: false,
                completenessHint: nil
            )
        }
        return applyCryptoGate(
            base: .completed,
            crypto: crypto,
            serverPlaintextAvailable: false,
            serverDecompileAvailable: false,
            completenessHint: nil
        )
    }
}
