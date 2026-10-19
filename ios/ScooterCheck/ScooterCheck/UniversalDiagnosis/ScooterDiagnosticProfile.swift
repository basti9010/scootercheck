import Foundation
import CryptoKit

/// Lesedefinition — nur dokumentierte, nicht zustandsverändernde Reads.
struct DiagnosticReadDefinition: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    /// `gatt` | `ninebotEnc2` | `xiaomiPlain` | `dis`
    var kind: String
    var serviceUUID: String?
    var characteristicUUID: String?
    var registerBoard: String?
    var registerIndex: Int?
    var notes: String?
}

/// Signiertes / gebündeltes Diagnoseprofil — keine ausführbaren Skripte.
struct ScooterDiagnosticProfile: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var manufacturer: String
    var modelPatterns: [String]
    var serviceUUIDs: [String]
    var protocolVersion: String
    var supportedReads: [DiagnosticReadDefinition]
    var referenceDataVersion: String?
    var approvalDataVersion: String?
    var source: String
    var sourceUrl: String?
    /// Freigegeben für automatische herstellerspezifische Diagnose.
    var verified: Bool
    /// Minimale App-Build-Nummer (CURRENT_PROJECT_VERSION als Int, falls gesetzt).
    var minAppBuild: Int?
    /// Native Stack-Adapter, den die App bereits kennt.
    var nativeStack: String?
    var updatedAt: String
    var notes: String?

    var supportLevelLabel: String {
        if verified, let nativeStack, !nativeStack.isEmpty {
            return "Vollständige Diagnose (\(nativeStack))"
        }
        if verified {
            return "Verifiziertes Profil (eingeschränkt)"
        }
        return "Nur Recherchehinweis — nicht für automatische Diagnose"
    }
}

struct ScooterDiagnosticProfileFile: Codable, Sendable {
    var version: Int
    var source: String
    var updatedAt: String
    var note: String?
    var profiles: [ScooterDiagnosticProfile]
}

enum DiagnosticProfileSignature {
    /// HMAC-SHA256 über kanonischem JSON der Profile-Liste (ohne Signaturfeld).
    /// Schlüssel nur aus Bundle / Secure Config — nie ungeschützt für Schreibzugriff.
    static func verify(payload: Data, signatureHex: String, keyMaterial: Data) -> Bool {
        let key = SymmetricKey(data: keyMaterial)
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        let expected = Data(mac).map { String(format: "%02x", $0) }.joined()
        return expected.lowercased() == signatureHex.lowercased()
    }

    static func bundledKeyMaterial() -> Data {
        // Deterministischer Bundle-Schlüssel nur für lokale Profilprüfung.
        // Online-Profile erfordern zusätzlich `verified` + Endpoint-Signatur.
        let seed = "scootercheck.diagnostic.profiles.v1"
        return Data(SHA256.hash(data: Data(seed.utf8)))
    }
}

enum DiagnosticSupportLevel: String, Codable, Sendable, Equatable {
    case fullNative
    case verifiedProfile
    case gattReadonly
    case researchHintOnly
    case none

    var label: String {
        switch self {
        case .fullNative: return "Natives Diagnoseprotokoll verfügbar"
        case .verifiedProfile: return "Verifiziertes Lesprofil verfügbar"
        case .gattReadonly: return "Nur standardisierte GATT-Reads möglich"
        case .researchHintOnly: return "Nur Recherchehinweis — kein sicheres Auslesen"
        case .none: return "Noch kein kompatibles Protokoll gefunden"
        }
    }
}

struct ProtocolCompatibilityResult: Equatable, Sendable {
    var profile: ScooterDiagnosticProfile?
    var supportLevel: DiagnosticSupportLevel
    var matchedOn: [String]
    var blockers: [String]
}
