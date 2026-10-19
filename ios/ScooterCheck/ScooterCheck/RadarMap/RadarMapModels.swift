import Foundation
import CoreLocation

// MARK: - Identity match confidence

enum RadarIdentityMatchConfidence: String, Codable, Sendable, Equatable {
    case confirmed
    case possible
    case similarOnly
    case unknown

    var label: String {
        switch self {
        case .confirmed: return "Bestätigte Zuordnung"
        case .possible: return "Mögliche Wiedererkennung"
        case .similarOnly: return "Ähnliches Gerät"
        case .unknown: return "Identität unbekannt"
        }
    }

    /// Darf als „dieselbe physische Gerätehistorie“ gezählt werden?
    var allowsHistoryMerge: Bool {
        self == .confirmed
    }
}

enum RadarIdentificationConfidence: String, Codable, Sendable, Equatable {
    case high, medium, unknown

    var label: String {
        switch self {
        case .high: return "Hoch"
        case .medium: return "Mittel"
        case .unknown: return "Unbekannt"
        }
    }
}

enum RadarDeviceKind: String, Codable, Sendable, Equatable {
    case confirmedScooter
    case possibleScooter
    case unknownBLE
}

// MARK: - Core records

struct RadarMapSession: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
}

struct RadarLocationSample: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isUsable: Bool {
        horizontalAccuracy > 0 && horizontalAccuracy < 200
    }
}

/// Eine zusammenhängende Empfangsphase (nicht jedes Advertising-Paket).
struct RadarSighting: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var sessionId: UUID
    var deviceIdentityId: UUID?
    /// Lokale iOS Peripheral-ID zum Zeitpunkt der Sichtung.
    var peripheralId: UUID
    var fingerprintKey: String
    var displayName: String
    var manufacturer: String?
    var model: String?
    var identificationConfidence: RadarIdentificationConfidence
    var identityMatchConfidence: RadarIdentityMatchConfidence
    var firstSeenAt: Date
    var lastSeenAt: Date
    var observationCount: Int
    var strongestRSSI: Int?
    var averageRSSI: Double?
    var smoothedRSSI: Double?
    var location: RadarLocationSample?
    var serviceUUIDs: [String]
    var manufacturerDataHex: String?
    var approvalStatusRaw: String?
    var deviceKind: RadarDeviceKind

    var durationSeconds: TimeInterval {
        max(0, lastSeenAt.timeIntervalSince(firstSeenAt))
    }

    var hasLocation: Bool { location?.isUsable == true }

    var signalLabel: String {
        guard let rssi = strongestRSSI ?? averageRSSI.map(Int.init) else { return "—" }
        switch rssi {
        case (-50)...0: return "Sehr stark"
        case (-65)...(-51): return "Stark"
        case (-80)...(-66): return "Mittel"
        default: return "Schwach"
        }
    }
}

struct RadarDeviceIdentity: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var primaryPeripheralId: UUID
    var fingerprintKey: String
    var displayName: String
    var manufacturer: String?
    var model: String?
    var firstSeenAt: Date
    var lastSeenAt: Date
    var sightingCount: Int
    var deviceKind: RadarDeviceKind
    var approvalStatusRaw: String?
}

struct HiddenRadarDevice: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var deviceIdentityId: UUID
    /// Zusätzlich: konkrete Peripheral-ID bei unsicherer Identität.
    var peripheralId: UUID?
    var hiddenAt: Date
    var reason: String?
    var suppressRadarNotifications: Bool
    var displayName: String
    var manufacturer: String?
    var model: String?
}

struct RadarMapSettings: Codable, Equatable, Sendable {
    var storeSightings: Bool
    var storeLocation: Bool
    var storeDeviceHistory: Bool
    var notifyRepeatSightings: Bool
    /// Minuten ohne Empfang → neue Sichtung (Default 15).
    var sightingGapMinutes: Int
    /// Aufbewahrung in Stunden; nil = manuell.
    var retentionHours: Int?
    var retainSightingsWhileHidden: Bool

    static let `default` = RadarMapSettings(
        storeSightings: false,
        storeLocation: false,
        storeDeviceHistory: true,
        notifyRepeatSightings: false,
        sightingGapMinutes: 15,
        retentionHours: 48,
        retainSightingsWhileHidden: false
    )

    private static let key = "radarMap.settings.v1"

    static func load() -> RadarMapSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(RadarMapSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Filters

enum RadarMapTimePreset: String, CaseIterable, Identifiable, Sendable {
    case h24, h48, d7, d14, all, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .h24: return "24 Std."
        case .h48: return "48 Std."
        case .d7: return "7 Tage"
        case .d14: return "14 Tage"
        case .all: return "Gesamt"
        case .custom: return "Zeitraum"
        }
    }

    func startDate(now: Date = Date(), customStart: Date? = nil) -> Date? {
        switch self {
        case .h24: return now.addingTimeInterval(-24 * 3600)
        case .h48: return now.addingTimeInterval(-48 * 3600)
        case .d7: return now.addingTimeInterval(-7 * 24 * 3600)
        case .d14: return now.addingTimeInterval(-14 * 24 * 3600)
        case .all: return nil
        case .custom: return customStart
        }
    }
}

enum RadarMapDeviceFilter: String, CaseIterable, Identifiable, Sendable {
    case all, confirmedScooter, possibleScooter, unknownBLE
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Alle Geräte"
        case .confirmedScooter: return "Nur bestätigte Scooter"
        case .possibleScooter: return "Mögliche Scooter"
        case .unknownBLE: return "Unbekannte BLE"
        }
    }
}

enum RadarMapRepeatScope: String, CaseIterable, Identifiable, Sendable {
    case withinTimeRange
    case entireHistory
    var id: String { rawValue }
    var label: String {
        switch self {
        case .withinTimeRange: return "Im gewählten Zeitraum"
        case .entireHistory: return "Gesamte Historie"
        }
    }
}

enum RadarMapApprovalFilter: String, CaseIterable, Identifiable, Sendable {
    case all, approved, unconfirmed, noApproval
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Alle"
        case .approved: return "Genehmigung dokumentiert"
        case .unconfirmed: return "Zulassungsstatus unklar"
        case .noApproval: return "Keine Genehmigung dokumentiert"
        }
    }
}

enum RadarMapSignalFilter: String, CaseIterable, Identifiable, Sendable {
    case all, mediumPlus, strong, veryStrong
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Alle"
        case .mediumPlus: return "Mittel oder stärker"
        case .strong: return "Stark"
        case .veryStrong: return "Sehr stark"
        }
    }
}

struct RadarMapFilter: Equatable, Sendable {
    var timePreset: RadarMapTimePreset = .h24
    var customStart: Date?
    var customEnd: Date?
    var deviceFilter: RadarMapDeviceFilter = .all
    var onlyRepeated: Bool = false
    var minSightings: Int = 2
    var repeatScope: RadarMapRepeatScope = .withinTimeRange
    var manufacturer: String? = nil
    var approval: RadarMapApprovalFilter = .all
    var signal: RadarMapSignalFilter = .all
    var identification: RadarIdentificationConfidence? = nil
    var showHidden: Bool = false
}

struct RadarMapSnapshotFile: Codable, Sendable {
    var version: Int
    var sessions: [RadarMapSession]
    var identities: [RadarDeviceIdentity]
    var sightings: [RadarSighting]
    var hidden: [HiddenRadarDevice]
}
