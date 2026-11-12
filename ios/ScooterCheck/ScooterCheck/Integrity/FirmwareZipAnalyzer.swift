import Foundation

/// Legacy-Ergebnisform — bridged von Firmware-Forensik 2.0.
struct FirmwareZipReport: Equatable, Sendable, Identifiable {
    var id: String { fileName + ":" + analyzedAt.timeIntervalSince1970.description }
    var fileName: String
    var analyzedAt: Date
    var formatLabel: String
    var displayName: String?
    var models: [String]
    var firmwareType: String?
    var compatibleBoards: [String]
    var declaredMd5: String?
    var computedMd5: String?
    var md5Matches: Bool?
    var firmSizeBytes: Int?
    var paramsText: String?
    var entryNames: [String]
    var findings: [Finding]
    var warnings: [String]
    var summary: String
    /// Vollständiger Forensikbericht (2.0).
    var forensic: FirmwareForensicReport?

    struct Finding: Equatable, Sendable, Identifiable {
        var id: String { "\(kind.rawValue)-\(title)-\(detail.prefix(40))" }
        var kind: Kind
        var title: String
        var detail: String
        var confidence: Confidence
        var source: String

        enum Kind: String, Sendable {
            case metadata
            case unlockGesture
            case speedLimit
            case featureFlag
            case region
            case customFirmware
            case note
        }

        enum Confidence: String, Sendable {
            case high
            case medium
            case low

            var label: String {
                switch self {
                case .high: return "hoch"
                case .medium: return "mittel"
                case .low: return "niedrig"
                }
            }
        }
    }
}

/// Fassade: leitet an Firmware-Forensik 2.0 weiter (Read-Only).
enum FirmwareZipAnalyzer {
    static func analyze(fileName: String, data: Data) -> FirmwareZipReport {
        analyze(fileName: fileName, data: data, vehicleContext: nil, references: [])
    }

    static func analyze(
        fileName: String,
        data: Data,
        vehicleContext: FirmwareVehicleContext?,
        references: [FirmwareReferenceRecord],
        preferredReferenceId: String? = nil
    ) -> FirmwareZipReport {
        let forensic = FirmwareForensicOrchestrator.analyze(
            fileName: fileName,
            data: data,
            references: references,
            preferredReferenceId: preferredReferenceId,
            vehicleContext: vehicleContext
        )
        return bridge(forensic)
    }

    static func bridge(_ forensic: FirmwareForensicReport) -> FirmwareZipReport {
        let primary = forensic.entries.first {
            $0.role == .firmPlain || $0.role == .firmEncrypted
        } ?? forensic.entries.first { FirmwarePackageLoader.baseName($0.path).lowercased().hasPrefix("firm") }

        let computedMd5 = primary?.digest.md5
        let declared = forensic.meta.declaredMd5
        let md5Matches: Bool? = {
            guard let declared, let computedMd5 else { return nil }
            return declared == computedMd5
        }()

        let formatLabel: String = {
            switch forensic.containerKind {
            case .zipV3: return "ScooterHacking ZIPv3"
            case .zipGeneric: return "ZIP (allgemein)"
            case .bareBinary: return "BIN"
            case .bareEncryptedBinary: return "BIN.ENC"
            case .json: return "JSON"
            case .text: return "TXT"
            case .unknown: return "Unbekannt"
            }
        }()

        let findings: [FirmwareZipReport.Finding] = forensic.evidence.prefix(40).map { item in
            let kind: FirmwareZipReport.Finding.Kind
            switch item.category {
            case .limitHint: kind = .speedLimit
            case .inputHint: kind = .unlockGesture
            case .filenameHint, .modeHint: kind = .featureFlag
            case .package: kind = .metadata
            default: kind = .note
            }
            let confidence: FirmwareZipReport.Finding.Confidence
            switch item.verifiability {
            case .confirmed: confidence = .high
            case .indicative: confidence = .medium
            case .unverified, .unavailable: confidence = .low
            }
            return .init(
                kind: kind,
                title: item.title,
                detail: item.detail,
                confidence: confidence,
                source: item.evidence
            )
        }

        return FirmwareZipReport(
            fileName: forensic.originalFileName,
            analyzedAt: forensic.analyzedAt,
            formatLabel: formatLabel,
            displayName: forensic.meta.displayName,
            models: forensic.meta.models,
            firmwareType: forensic.meta.type,
            compatibleBoards: forensic.meta.compatible,
            declaredMd5: declared,
            computedMd5: computedMd5,
            md5Matches: md5Matches,
            firmSizeBytes: primary?.digest.byteCount,
            paramsText: nil,
            entryNames: forensic.entries.map(\.path),
            findings: findings,
            warnings: forensic.limits,
            summary: forensic.summary,
            forensic: forensic
        )
    }
}
