import Foundation

// MARK: - Kontroll-Ampel (Straßenkontrolle)

/// Kurzurteil für die Kontrolle — getrennt vom technischen VerdictLevel.
/// Grün nur bei ausreichender Auslese und ohne Fremd-Antriebs-Hinweis.
enum ControlAssessment: String, Codable, CaseIterable, Sendable {
    /// Limit gelesen, ≤ Typ (+ Puffer), technisch unauffällig, kein Fremd-BLE-Hinweis.
    case typkonform
    /// Limit/Peak/Session/Fremd-BLE oder technisches Urteil auffällig.
    case auffaellig
    /// Mindest-Evidenz fehlt (kein Limit) — kein „grün“.
    case unvollstaendig

    var label: String {
        switch self {
        case .typkonform: return "Typkonform"
        case .auffaellig: return "Auffällig"
        case .unvollstaendig: return "Auslese unvollständig"
        }
    }

    var shortHint: String {
        switch self {
        case .typkonform:
            return "Eingestelltes Limit und geprüfte Werte passen zum Typprofil."
        case .auffaellig:
            return "Abweichung von der typischen Begrenzung oder Hinweis auf Fremdmodul."
        case .unvollstaendig:
            return "Geschwindigkeitslimit konnte nicht zuverlässig ausgelesen werden — kein Typkonform-Ergebnis."
        }
    }
}

/// Eng gefilterter Hinweis auf mögliches Fremd-Antriebs-BLE (z. B. VESC-Dongle).
struct ForeignBleSighting: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(name)|\(rssi)|\(reason)" }
    let name: String
    let rssi: Int
    let reason: String
}

enum ForeignBleDetector {
    /// Nur sehr nah — Wohnzimmer-TV und Nachbar-Kopfhörer sollen nicht zählen.
    static let minimumRssi = -60

    /// Namen, die nach Aftermarket-ESC / VESC-Tool klingen — bewusst eng.
    private static let nameTokens = [
        "VESC", "MAKERBASE", "FLIPSKY", "MAYTECH", "FOCBOX", "UNITY ESC",
        "STORMCORE", "ENNOID", "TRAMPA", "SPINTEN", "LITTLE FOC", "MINI FOC",
        "BASES", "ESC BLE", "BLE ESC"
    ]

    static func looksLikeForeignDriveBle(name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        let upper = name.uppercased()
        if BleClient.isLikelyScooterName(name) { return false }
        // Alltagsgeräte bleiben draußen (TV, Audio, Phone…).
        let consumer = [
            "TV", "OLED", "IPHONE", "IPAD", "WATCH", "AIRPOD", "SONOS", "BOSE", "JBL",
            "HEADPHONE", "SPEAKER", "SAMSUNG", "LG ", "SONY", "XBOX", "PLAYSTATION",
            "NUKI", "HUE ", "THERMOSTAT", "GALAXY", "PIXEL"
        ]
        if consumer.contains(where: { upper.contains($0) }) { return false }
        return nameTokens.contains(where: { upper.contains($0) })
    }

    /// Nur starke, namensbasierte Treffer — keine generischen Nordic-UART-Falschalarme.
    static func sightings(
        from devices: [(name: String, rssi: Int, looksLikeScooter: Bool)],
        excludingNames: Set<String> = []
    ) -> [ForeignBleSighting] {
        var out: [ForeignBleSighting] = []
        for device in devices {
            guard device.rssi >= minimumRssi, device.rssi < 20 else { continue }
            guard !device.looksLikeScooter else { continue }
            let trimmed = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("Ohne Namen") else { continue }
            if excludingNames.contains(where: { trimmed.caseInsensitiveCompare($0) == .orderedSame }) {
                continue
            }
            guard looksLikeForeignDriveBle(name: trimmed) else { continue }
            out.append(ForeignBleSighting(
                name: trimmed,
                rssi: device.rssi,
                reason: "Name deutet auf Aftermarket-Antriebs-BLE hin (starkes Signal)"
            ))
        }
        // Deduplizieren nach Name, stärkstes Signal behalten.
        var best: [String: ForeignBleSighting] = [:]
        for s in out {
            let key = s.name.uppercased()
            if let prev = best[key], prev.rssi >= s.rssi { continue }
            best[key] = s
        }
        return best.values.sorted { $0.rssi > $1.rssi }
    }
}

enum ControlAssessmentEngine {
    /// Limit muss gelesen sein — Peak allein reicht nicht für „Typkonform“.
    static func hasMinimumSpeedEvidence(_ reading: IntegrityReading) -> Bool {
        reading.speedLimitKmh != nil || reading.speedMaxKmh != nil
    }

    static func assess(
        reading: IntegrityReading,
        profile: ScooterProfile,
        technicalVerdict: VerdictLevel
    ) -> ControlAssessment {
        let foreign = !(reading.foreignBleCandidates ?? []).isEmpty
        let complete = hasMinimumSpeedEvidence(reading) && !reading.rawRegisters.isEmpty

        if !complete { return .unvollstaendig }
        if foreign { return .auffaellig }

        let limit = reading.speedLimitKmh ?? reading.speedMaxKmh
        let peak = reading.peakSpeedKmh
        let rated = profile.ratedMaxKmh
        let suspect = profile.tuningSuspectKmh

        if let limit, limit > suspect { return .auffaellig }
        if let peak, peak > suspect { return .auffaellig }
        if reading.hiddenTuningDetected == true { return .auffaellig }

        switch technicalVerdict {
        case .stock:
            // Limit klar über Typ (+1) auch ohne Suspect-Schwelle → auffällig.
            if let limit, limit > rated + 1 { return .auffaellig }
            return .typkonform
        case .auffaellig, .hinweise, .eindeutig:
            return .auffaellig
        }
    }

    static func summaryLine(
        assessment: ControlAssessment,
        reading: IntegrityReading,
        profile: ScooterProfile
    ) -> String {
        let limit = Format.kmh.format(reading.speedLimitKmh ?? reading.speedMaxKmh)
        let peak = Format.kmh.format(reading.peakSpeedKmh)
        let soll = Format.kmh.format(Optional(profile.ratedMaxKmh))
        switch assessment {
        case .typkonform:
            return "Limit \(limit) · Peak \(peak) · Soll ≤ \(soll)"
        case .auffaellig:
            if let first = (reading.foreignBleCandidates ?? []).first {
                return "Limit \(limit) · Peak \(peak) · Zusatz-BLE: \(first.name)"
            }
            return "Limit \(limit) · Peak \(peak) · Soll ≤ \(soll)"
        case .unvollstaendig:
            return "Limit \(limit) · Peak \(peak) — Auslese für Typprüfung unzureichend"
        }
    }
}
