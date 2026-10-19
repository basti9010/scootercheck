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
    /// Nur gesetzt bei belastbarer Geräteidentität — nie über schwache Fingerprints.
    var deviceIdentityId: UUID?
    /// Lokale Peripheral-ID; bei unsicherer Identität die einzige Bindung.
    var peripheralId: UUID?
    var hiddenAt: Date
    var reason: String?
    var suppressRadarNotifications: Bool
    /// Pro-Gerät-Flag; globales Setting `retainSightingsWhileHidden` steuert den Default.
    var retainFutureSightings: Bool
    /// true = Identity bestätigt; false = nur diese Peripheral-ID.
    var identityBound: Bool
    var displayName: String
    var manufacturer: String?
    var model: String?

    var bindingNote: String? {
        identityBound ? nil : "Nur diese Gerätekennung. Wechselnde BLE-IDs können erneut erscheinen."
    }

    enum CodingKeys: String, CodingKey {
        case id, deviceIdentityId, peripheralId, hiddenAt, reason
        case suppressRadarNotifications, retainFutureSightings, identityBound
        case displayName, manufacturer, model
    }

    init(
        id: UUID,
        deviceIdentityId: UUID?,
        peripheralId: UUID?,
        hiddenAt: Date,
        reason: String?,
        suppressRadarNotifications: Bool,
        retainFutureSightings: Bool,
        identityBound: Bool,
        displayName: String,
        manufacturer: String?,
        model: String?
    ) {
        self.id = id
        self.deviceIdentityId = deviceIdentityId
        self.peripheralId = peripheralId
        self.hiddenAt = hiddenAt
        self.reason = reason
        self.suppressRadarNotifications = suppressRadarNotifications
        self.retainFutureSightings = retainFutureSightings
        self.identityBound = identityBound
        self.displayName = displayName
        self.manufacturer = manufacturer
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        deviceIdentityId = try c.decodeIfPresent(UUID.self, forKey: .deviceIdentityId)
        peripheralId = try c.decodeIfPresent(UUID.self, forKey: .peripheralId)
        hiddenAt = try c.decode(Date.self, forKey: .hiddenAt)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        suppressRadarNotifications = try c.decodeIfPresent(Bool.self, forKey: .suppressRadarNotifications) ?? true
        retainFutureSightings = try c.decodeIfPresent(Bool.self, forKey: .retainFutureSightings) ?? false
        identityBound = try c.decodeIfPresent(Bool.self, forKey: .identityBound)
            ?? (deviceIdentityId != nil && reason != "peripheral-only")
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "Gerät"
        manufacturer = try c.decodeIfPresent(String.self, forKey: .manufacturer)
        model = try c.decodeIfPresent(String.self, forKey: .model)
    }
}

/// Aufbewahrungsdauer der Radar-Karten-Sichtungen.
enum RadarMapRetentionChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case hours24
    case hours48
    case days7
    case days14
    case untilManualDeletion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hours24: return "24 Stunden"
        case .hours48: return "48 Stunden"
        case .days7: return "7 Tage"
        case .days14: return "14 Tage"
        case .untilManualDeletion: return "Bis zur manuellen Löschung"
        }
    }

    var hours: Int? {
        switch self {
        case .hours24: return 24
        case .hours48: return 48
        case .days7: return 168
        case .days14: return 336
        case .untilManualDeletion: return nil
        }
    }

    static func from(hours: Int?) -> RadarMapRetentionChoice {
        switch hours {
        case 24: return .hours24
        case 48: return .hours48
        case 168: return .days7
        case 336: return .days14
        case nil, .some(-1): return .untilManualDeletion
        default: return .untilManualDeletion
        }
    }
}

struct RadarMapSettings: Codable, Equatable, Sendable {
    var storeSightings: Bool
    var storeLocation: Bool
    var storeDeviceHistory: Bool
    var notifyRepeatSightings: Bool
    var sightingGapMinutes: Int
    /// nil = bis zur manuellen Löschung.
    var retentionHours: Int?
    var retainSightingsWhileHidden: Bool

    var retentionChoice: RadarMapRetentionChoice {
        get { RadarMapRetentionChoice.from(hours: retentionHours) }
        set { retentionHours = newValue.hours }
    }

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
    private static let manualRetentionSentinel = -1

    enum CodingKeys: String, CodingKey {
        case storeSightings, storeLocation, storeDeviceHistory, notifyRepeatSightings
        case sightingGapMinutes, retentionHours, retainSightingsWhileHidden
    }

    init(
        storeSightings: Bool,
        storeLocation: Bool,
        storeDeviceHistory: Bool,
        notifyRepeatSightings: Bool,
        sightingGapMinutes: Int,
        retentionHours: Int?,
        retainSightingsWhileHidden: Bool
    ) {
        self.storeSightings = storeSightings
        self.storeLocation = storeLocation
        self.storeDeviceHistory = storeDeviceHistory
        self.notifyRepeatSightings = notifyRepeatSightings
        self.sightingGapMinutes = sightingGapMinutes
        self.retentionHours = retentionHours
        self.retainSightingsWhileHidden = retainSightingsWhileHidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        storeSightings = try c.decodeIfPresent(Bool.self, forKey: .storeSightings) ?? false
        storeLocation = try c.decodeIfPresent(Bool.self, forKey: .storeLocation) ?? false
        storeDeviceHistory = try c.decodeIfPresent(Bool.self, forKey: .storeDeviceHistory) ?? true
        notifyRepeatSightings = try c.decodeIfPresent(Bool.self, forKey: .notifyRepeatSightings) ?? false
        sightingGapMinutes = try c.decodeIfPresent(Int.self, forKey: .sightingGapMinutes) ?? 15
        retainSightingsWhileHidden = try c.decodeIfPresent(Bool.self, forKey: .retainSightingsWhileHidden) ?? false
        if let raw = try c.decodeIfPresent(Int.self, forKey: .retentionHours) {
            retentionHours = raw == Self.manualRetentionSentinel ? nil : raw
        } else {
            retentionHours = 48
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(storeSightings, forKey: .storeSightings)
        try c.encode(storeLocation, forKey: .storeLocation)
        try c.encode(storeDeviceHistory, forKey: .storeDeviceHistory)
        try c.encode(notifyRepeatSightings, forKey: .notifyRepeatSightings)
        try c.encode(sightingGapMinutes, forKey: .sightingGapMinutes)
        try c.encode(retainSightingsWhileHidden, forKey: .retainSightingsWhileHidden)
        try c.encode(retentionHours ?? Self.manualRetentionSentinel, forKey: .retentionHours)
    }

    static func load() -> RadarMapSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(RadarMapSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
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
