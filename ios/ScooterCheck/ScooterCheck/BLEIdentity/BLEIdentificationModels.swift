import Foundation

// MARK: - Confidence / evidence

enum BLEIdentificationConfidence: String, Codable, Sendable, Equatable {
    case high
    case medium
    case low
    case unknown

    var label: String {
        switch self {
        case .high: return "Hoch"
        case .medium: return "Mittel"
        case .low: return "Niedrig"
        case .unknown: return "Unbekannt"
        }
    }
}

enum BLEIdentificationSource: String, Codable, Sendable, Equatable {
    case local
    case online
    case gatt
    case combined
}

enum BLEDeviceCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case eScooter
    case smartphone
    case smartwatch
    case audio
    case television
    case computer
    case smartHome
    case sensor
    case beacon
    case wearable
    case vehicle
    case unknown

    var label: String {
        switch self {
        case .eScooter: return "E-Scooter"
        case .smartphone: return "Smartphone"
        case .smartwatch: return "Smartwatch"
        case .audio: return "Audio"
        case .television: return "Fernseher / Media"
        case .computer: return "Computer / Zubehör"
        case .smartHome: return "Smart-Home"
        case .sensor: return "Sensor"
        case .beacon: return "Beacon"
        case .wearable: return "Wearable"
        case .vehicle: return "Fahrzeug"
        case .unknown: return "Unbekannt"
        }
    }
}

struct IdentificationEvidence: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var title: String
    var detail: String
    /// Unterstützt (+) oder widerspricht (−) der Zuordnung.
    var supports: Bool

    init(id: String = UUID().uuidString, title: String, detail: String, supports: Bool = true) {
        self.id = id
        self.title = title
        self.detail = detail
        self.supports = supports
    }
}

struct BLEIdentificationResult: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var deviceId: UUID
    var manufacturer: String?
    var manufacturerCompanyId: UInt16?
    var deviceCategory: BLEDeviceCategory?
    var model: String?
    var protocolProfile: String?
    var confidence: BLEIdentificationConfidence
    var evidence: [IdentificationEvidence]
    var contradictions: [IdentificationEvidence]
    var source: BLEIdentificationSource
    var analyzedAt: Date
    var listTitle: String
    var listSubtitle: String?
    /// Nur bei belastbarer Scooter-Klassifikation true — für Radar.
    var radarEligibleScooter: Bool
    var onlineSourceNote: String?
    var onlineFetchedAt: Date?

    static func unknown(deviceId: UUID, displayName: String) -> BLEIdentificationResult {
        BLEIdentificationResult(
            id: UUID(),
            deviceId: deviceId,
            manufacturer: nil,
            manufacturerCompanyId: nil,
            deviceCategory: .unknown,
            model: nil,
            protocolProfile: nil,
            confidence: .unknown,
            evidence: [
                IdentificationEvidence(
                    id: "none",
                    title: "Keine belastbare Zuordnung",
                    detail: "Verfügbare Advertisement-Daten reichen für Hersteller/Klasse/Modell nicht aus."
                )
            ],
            contradictions: [],
            source: .local,
            analyzedAt: Date(),
            listTitle: displayName,
            listSubtitle: nil,
            radarEligibleScooter: false,
            onlineSourceNote: nil,
            onlineFetchedAt: nil
        )
    }
}

// MARK: - Settings

struct BLEIdentificationSettings: Codable, Equatable, Sendable {
    var onlineIdentificationEnabled: Bool
    var onlineConsentAccepted: Bool
    var onlineConsentAcceptedAt: Date?

    static let `default` = BLEIdentificationSettings(
        onlineIdentificationEnabled: false,
        onlineConsentAccepted: false,
        onlineConsentAcceptedAt: nil
    )

    private static let defaultsKey = "bleIdentification.settings.v1"

    static func load() -> BLEIdentificationSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(BLEIdentificationSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

// MARK: - Manufacturer hex helpers

enum BLEManufacturerParsing {
    /// BLE Company Identifier (little-endian) aus Manufacturer Data Hex.
    /// Akzeptiert sowohl „4C00…“ als auch „4C 00 …“.
    static func companyId(fromManufacturerHex hex: String?) -> UInt16? {
        guard let hex else { return nil }
        let compact = hex
            .uppercased()
            .filter { $0.isHexDigit }
        guard compact.count >= 4,
              let lo = UInt8(compact.prefix(2), radix: 16),
              let hi = UInt8(compact.dropFirst(2).prefix(2), radix: 16) else { return nil }
        return UInt16(lo) | (UInt16(hi) << 8)
    }

    static func compactHex(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let c = hex.uppercased().filter { $0.isHexDigit }
        return c.isEmpty ? nil : c
    }
}
