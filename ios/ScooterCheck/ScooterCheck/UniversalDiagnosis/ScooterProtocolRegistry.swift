import Foundation

/// Zentrale Registry gebündelter + optional online geladener Diagnoseprofile.
@MainActor
final class ScooterProtocolRegistry: ObservableObject {
    static let shared = ScooterProtocolRegistry()

    @Published private(set) var bundled: [ScooterDiagnosticProfile] = []
    @Published private(set) var onlineCached: [ScooterDiagnosticProfile] = []
    @Published private(set) var loadNote: String?

    private let onlineCacheKey = "scooterDiagnostic.onlineProfiles.v1"

    private init() {
        reloadBundled()
        loadOnlineCache()
    }

    var allProfiles: [ScooterDiagnosticProfile] {
        bundled + onlineCached.filter { remote in
            !bundled.contains(where: { $0.id == remote.id })
        }
    }

    func reloadBundled() {
        guard let url = Bundle.main.url(forResource: "scooter_diagnostic_profiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ScooterDiagnosticProfileFile.self, from: data) else {
            bundled = []
            loadNote = "Gebündelte Profildatei fehlt."
            return
        }
        bundled = file.profiles
        loadNote = "\(file.profiles.count) gebündelte Profile · v\(file.version)"
    }

    func verifiedProfilesForDiagnosis() -> [ScooterDiagnosticProfile] {
        allProfiles.filter(\.verified)
    }

    func researchHints() -> [ScooterDiagnosticProfile] {
        allProfiles.filter { !$0.verified }
    }

    enum IngestError: Error, Equatable, LocalizedError {
        case missingSignature
        case invalidSignature
        case invalidJSON
        case noCompatibleProfiles

        var errorDescription: String? {
            switch self {
            case .missingSignature:
                return "Online-Profile ohne Signatur werden nicht übernommen."
            case .invalidSignature:
                return "Signatur ungültig — Profile verworfen."
            case .invalidJSON:
                return "Profil-JSON ungültig."
            case .noCompatibleProfiles:
                return "Keine kompatiblen verifizierten Profile in der Antwort."
            }
        }
    }

    /// Nimmt nur signierte, verifizierte, kompatible Online-Profile an.
    func ingestOnlineProfiles(
        fileData: Data,
        signatureHex: String?,
        requireSignature: Bool
    ) -> Result<Int, IngestError> {
        if requireSignature {
            guard let signatureHex, !signatureHex.isEmpty else {
                return .failure(.missingSignature)
            }
            let ok = DiagnosticProfileSignature.verify(
                payload: fileData,
                signatureHex: signatureHex,
                keyMaterial: DiagnosticProfileSignature.bundledKeyMaterial()
            )
            guard ok else {
                return .failure(.invalidSignature)
            }
        }
        guard let file = try? JSONDecoder().decode(ScooterDiagnosticProfileFile.self, from: fileData) else {
            return .failure(.invalidJSON)
        }
        let appBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
        let accepted = file.profiles.filter { profile in
            guard profile.verified else { return false }
            if let min = profile.minAppBuild, appBuild < min { return false }
            // Ohne nativeStack nur DIS/gatt — nativeStack null + verified erlaubt gatt
            return true
        }
        guard !accepted.isEmpty else {
            return .failure(.noCompatibleProfiles)
        }
        onlineCached = accepted
        if let encoded = try? JSONEncoder().encode(accepted) {
            UserDefaults.standard.set(encoded, forKey: onlineCacheKey)
        }
        return .success(accepted.count)
    }

    func clearOnlineCache() {
        onlineCached = []
        UserDefaults.standard.removeObject(forKey: onlineCacheKey)
    }

    private func loadOnlineCache() {
        guard let data = UserDefaults.standard.data(forKey: onlineCacheKey),
              let decoded = try? JSONDecoder().decode([ScooterDiagnosticProfile].self, from: data) else {
            return
        }
        onlineCached = decoded.filter(\.verified)
    }
}

/// Eingabe für Protokoll-Matching — ohne CBPeripheral (testbar).
struct ProtocolMatchInput: Equatable, Sendable {
    var name: String
    var cryptoName: String
    var modelLabel: String?
    var serviceUUIDs: [String]
    var looksLikeScooter: Bool
    var suggestedProfileRaw: String?
    var isConnectable: Bool?

    static func from(device: ScannedDevice) -> ProtocolMatchInput {
        ProtocolMatchInput(
            name: device.name,
            cryptoName: device.cryptoName,
            modelLabel: device.modelLabel,
            serviceUUIDs: device.serviceUUIDs,
            looksLikeScooter: device.looksLikeScooter,
            suggestedProfileRaw: device.suggestedProfile?.rawValue,
            isConnectable: device.isConnectable
        )
    }
}

enum ProtocolCompatibilityEngine {
    static func evaluate(
        device: ScannedDevice,
        identity: BLEIdentificationResult?,
        profiles: [ScooterDiagnosticProfile]
    ) -> ProtocolCompatibilityResult {
        evaluate(input: .from(device: device), identity: identity, profiles: profiles)
    }

    static func evaluate(
        input: ProtocolMatchInput,
        identity: BLEIdentificationResult?,
        profiles: [ScooterDiagnosticProfile]
    ) -> ProtocolCompatibilityResult {
        var matchedOn: [String] = []
        var blockers: [String] = []
        let hay = [
            input.cryptoName,
            input.name,
            input.modelLabel ?? "",
            identity?.manufacturer ?? "",
            identity?.model ?? "",
            ExtendedScooterModelHint.recognize(bleName: input.cryptoName)?.title ?? ""
        ].joined(separator: " ").uppercased()

        let services = Set(input.serviceUUIDs.map { BLEKnownServiceUUID.normalize($0) })

        // Native Ninebot / Xiaomi zuerst
        if let native = profiles.first(where: { $0.verified && $0.nativeStack == "ninebotEnc2" }) {
            let uart = services.contains(where: {
                $0.contains("696E65626F74") || $0.contains("6E400001B5A3F393E0A9E50E24DCCA9E")
            })
            let nameHit = native.modelPatterns.contains { hay.contains($0.uppercased()) }
            if uart || nameHit || input.suggestedProfileRaw != nil {
                if uart { matchedOn.append("Ninebot/Nordic UART") }
                if nameHit { matchedOn.append("Namensmuster Ninebot") }
                if input.suggestedProfileRaw != nil { matchedOn.append("BleModelHint-Profil") }
                return ProtocolCompatibilityResult(
                    profile: native,
                    supportLevel: .fullNative,
                    matchedOn: matchedOn,
                    blockers: []
                )
            }
        }

        if let xiaomi = profiles.first(where: { $0.verified && $0.nativeStack == "xiaomiPlain" }) {
            let nordic = services.contains(where: { $0.contains("6E400001B5A3F393E0A9E50E24DCCA9E") })
            let patternHit = xiaomi.modelPatterns.contains { hay.contains($0.uppercased()) }
            // Mi-Home-IDs wie „xiaomi.scooter.6“ (Punkt statt Leerzeichen).
            let miHomeId = hay.contains("XIAOMI") && hay.contains("SCOOTER")
            let nameHit = patternHit || miHomeId || hay.contains("MISCOOTER")
            if (nordic && nameHit) || (nameHit && input.looksLikeScooter) {
                matchedOn.append(contentsOf: [nameHit ? "Xiaomi-Name" : nil, nordic ? "Nordic UART" : nil].compactMap { $0 })
                return ProtocolCompatibilityResult(
                    profile: xiaomi,
                    supportLevel: .fullNative,
                    matchedOn: matchedOn,
                    blockers: []
                )
            }
        }

        // Research hints by manufacturer name
        for hint in profiles where !hint.verified {
            if hint.modelPatterns.contains(where: { hay.contains($0.uppercased()) }) {
                matchedOn.append("Herstellerhinweis \(hint.manufacturer)")
                blockers.append("Kein freigegebenes Lesprotokoll für \(hint.manufacturer).")
                let hasDIS = services.contains(where: { $0.hasSuffix("180A") || $0 == "180A" })
                    || input.serviceUUIDs.contains(where: { $0.uppercased().contains("180A") })
                if hasDIS, let dis = profiles.first(where: { $0.nativeStack == "gattDis" && $0.verified }) {
                    matchedOn.append("Device Information Service")
                    return ProtocolCompatibilityResult(
                        profile: dis,
                        supportLevel: .gattReadonly,
                        matchedOn: matchedOn,
                        blockers: blockers
                    )
                }
                return ProtocolCompatibilityResult(
                    profile: hint,
                    supportLevel: .researchHintOnly,
                    matchedOn: matchedOn,
                    blockers: blockers
                )
            }
        }

        // Generisches DIS
        if input.serviceUUIDs.contains(where: { $0.uppercased().contains("180A") }),
           let dis = profiles.first(where: { $0.nativeStack == "gattDis" && $0.verified }) {
            matchedOn.append("Device Information Service")
            return ProtocolCompatibilityResult(
                profile: dis,
                supportLevel: .gattReadonly,
                matchedOn: matchedOn,
                blockers: ["Kein proprietäres Scooter-Protokoll erkannt."]
            )
        }

        blockers.append("Kein kompatibles Diagnoseprofil gefunden.")
        if input.isConnectable == false {
            blockers.append("Gerät wirbt nicht als verbindbar.")
        }
        return ProtocolCompatibilityResult(
            profile: nil,
            supportLevel: .none,
            matchedOn: matchedOn,
            blockers: blockers
        )
    }
}
