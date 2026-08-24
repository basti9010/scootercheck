import Foundation

// MARK: - Scooter Profile

enum ScooterProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case zt3ProD
    case zt3ProE

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zt3ProD: return "Ninebot ZT3 Pro D (20 km/h)"
        case .zt3ProE: return "Ninebot ZT3 Pro E (25 km/h)"
        }
    }

    var shortLabel: String {
        switch self {
        case .zt3ProD: return "ZT3 Pro D"
        case .zt3ProE: return "ZT3 Pro E"
        }
    }

    var ratedMaxKmh: Double {
        switch self {
        case .zt3ProD: return 20
        case .zt3ProE: return 25
        }
    }

    /// Ab dieser Höchstgeschwindigkeit (Auslesewert) ist eine Abweichung verdächtig.
    var tuningSuspectKmh: Double {
        switch self {
        case .zt3ProD: return 22
        case .zt3ProE: return 27
        }
    }

    /// Ab dieser Höchstgeschwindigkeit (Auslesewert) gilt eine erhebliche Abweichung als wahrscheinlich.
    var tuningClearKmh: Double {
        switch self {
        case .zt3ProD: return 25
        case .zt3ProE: return 32
        }
    }

    /// Typische Seriennummer-Präfixe / Regionen für werkseitige Zuordnung.
    var stockSerialHints: [String] {
        switch self {
        case .zt3ProD:
            return ["N4GSD", "N4GSE", "N4GSC", "DE", "EU"]
        case .zt3ProE:
            return ["N4GSE", "N4GSC", "EU", "FR", "IT", "ES"]
        }
    }

    var legalText: String {
        switch self {
        case .zt3ProD:
            return """
            Typgenehmigung und Betriebserlaubnis für den deutschen Markt (Klasse L1e-B, \
            bauartbedingte Höchstgeschwindigkeit 20 km/h). Abweichungen von werkseitigen \
            Parametern können die Betriebserlaubnis und Versicherungsschutz beeinträchtigen.
            """
        case .zt3ProE:
            return """
            EU-Typgenehmigung mit bauartbedingter Höchstgeschwindigkeit 25 km/h. \
            Nicht zulässige Änderungen an Firmware oder Steuerparametern können den \
            Betrieb im öffentlichen Straßenverkehr unzulässig machen.
            """
        }
    }
}

// MARK: - Fact Status & Verdict

enum FactStatus: String, Codable, CaseIterable, Sendable {
    case regelkonform = "regelkonform"
    case abweichend = "abweichend"
    case erheblichAbweichend = "erheblich abweichend"
    case nichtFeststellbar = "nicht feststellbar"

    var label: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .regelkonform: return 0
        case .abweichend: return 1
        case .erheblichAbweichend: return 2
        case .nichtFeststellbar: return 3
        }
    }
}

enum VerdictLevel: String, Codable, CaseIterable, Sendable {
    case stock
    case watch
    case tuned

    var label: String {
        switch self {
        case .stock: return "Serienzustand"
        case .watch: return "Auffälligkeiten"
        case .tuned: return "Manipuliert / getunt"
        }
    }

    var laymanText: String {
        switch self {
        case .stock:
            return """
            Die ausgelesenen Werte entsprechen überwiegend dem werkseitigen Sollzustand. \
            Es liegen keine hinreichenden Anhaltspunkte für eine unzulässige Leistungssteigerung vor.
            """
        case .watch:
            return """
            Einzelne Auslesewerte weichen vom Soll ab oder sind nicht eindeutig zuordenbar. \
            Eine abschließende Bewertung erfordert zusätzliche Prüfungen oder Sachverständigengutachten.
            """
        case .tuned:
            return """
            Mehrere unabhängige Anhaltspunkte sprechen für eine Abweichung vom werkseitigen Zustand \
            (z. B. erhöhte Geschwindigkeitswerte, Firmware-Merkmale oder Seriennummer-Inkonsistenzen).
            """
        }
    }
}

// MARK: - Display Format

enum Format: String, Codable, Sendable {
    case kmh
    case num
    case km
    case minutes
    case code

    func format(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        switch self {
        case .kmh: return "\(value) km/h"
        case .num: return value
        case .km: return "\(value) km"
        case .minutes: return "\(value) min"
        case .code: return value
        }
    }

    func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch self {
        case .kmh: return String(format: "%.1f km/h", value)
        case .num: return String(format: "%.0f", value)
        case .km: return String(format: "%.1f km", value)
        case .minutes: return String(format: "%.0f min", value)
        case .code: return String(format: "%.0f", value)
        }
    }

    func format(_ value: Int?) -> String {
        guard let value else { return "—" }
        switch self {
        case .kmh: return "\(value) km/h"
        case .num: return "\(value)"
        case .km: return "\(value) km"
        case .minutes: return "\(value) min"
        case .code: return "\(value)"
        }
    }
}

enum SerialRegion: String, Codable, CaseIterable, Sendable {
    case eu = "EU"
    case de = "DE"
    case us = "US"
    case cn = "CN"
    case unknown = "unbekannt"

    var label: String {
        switch self {
        case .eu: return "Europa (EU)"
        case .de: return "Deutschland (DE)"
        case .us: return "USA (US)"
        case .cn: return "China (CN)"
        case .unknown: return "Nicht zuordenbar"
        }
    }
}

// MARK: - Raw Register

struct RawRegister: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(address)-\(index)" }
    let address: String
    let index: Int
    let name: String
    let valueHex: String
    let valueDecoded: String?
    let note: String?

    init(
        address: String,
        index: Int = 0,
        name: String,
        valueHex: String,
        valueDecoded: String? = nil,
        note: String? = nil
    ) {
        self.address = address
        self.index = index
        self.name = name
        self.valueHex = valueHex
        self.valueDecoded = valueDecoded
        self.note = note
    }
}

// MARK: - Integrity Reading

struct IntegrityReading: Codable, Hashable, Sendable {
    // Seriennummern
    var serialDisplay: String?
    var serialExpected: String?
    var serialMcu: String?
    var serialBle: String?
    var serialBms: String?
    var serialVcu: String?

    // Geschwindigkeiten
    var speedCurrentKmh: Double?
    var speedMaxKmh: Double?
    var speedRatedKmh: Double?
    var speedLimitKmh: Double?
    var peakSpeedKmh: Double?

    // Kilometerstände / Fahrzeiten
    var odometerKm: Double?
    var tripKm: Double?
    var remainKm: Double?
    var rideTimeMinutes: Int?
    var totalRideTimeMinutes: Int?
    var chargeCycles: Int?

    // Firmware
    var fwMcu: String?
    var fwBle: String?
    var fwBms: String?
    var fwVcu: String?
    var fwEsc: String?
    var fwAppCustom: Bool?

    // Batterie
    var batteryPercent: Int?
    var batteryVoltage: Double?
    var batteryCurrent: Double?
    var batteryHealth: Int?
    var batteryTempC: Double?

    // Temperaturen
    var mcuTempC: Double?
    var motorTempC: Double?

    // Fehler / Alarm
    var errorCode: String?
    var alarmCode: String?
    var errorActive: Bool?

    // Leistung
    var peakPowerW: Double?

    // Flags
    var panicModeActive: Bool?
    var hiddenTuningDetected: Bool?
    var safeLockActive: Bool?
    var unboundRebound: Bool?

    // Sonstiges
    var physicalMarks: [String]
    var gearMode: Int?
    var gearMax: Int?
    var protocolGen: Int?
    var evidenceSha256: String?
    var rawRegisters: [RawRegister]
    var liveBoards: [String]

    init(
        serialDisplay: String? = nil,
        serialExpected: String? = nil,
        serialMcu: String? = nil,
        serialBle: String? = nil,
        serialBms: String? = nil,
        serialVcu: String? = nil,
        speedCurrentKmh: Double? = nil,
        speedMaxKmh: Double? = nil,
        speedRatedKmh: Double? = nil,
        speedLimitKmh: Double? = nil,
        peakSpeedKmh: Double? = nil,
        odometerKm: Double? = nil,
        tripKm: Double? = nil,
        remainKm: Double? = nil,
        rideTimeMinutes: Int? = nil,
        totalRideTimeMinutes: Int? = nil,
        chargeCycles: Int? = nil,
        fwMcu: String? = nil,
        fwBle: String? = nil,
        fwBms: String? = nil,
        fwVcu: String? = nil,
        fwEsc: String? = nil,
        fwAppCustom: Bool? = nil,
        batteryPercent: Int? = nil,
        batteryVoltage: Double? = nil,
        batteryCurrent: Double? = nil,
        batteryHealth: Int? = nil,
        batteryTempC: Double? = nil,
        mcuTempC: Double? = nil,
        motorTempC: Double? = nil,
        errorCode: String? = nil,
        alarmCode: String? = nil,
        errorActive: Bool? = nil,
        peakPowerW: Double? = nil,
        panicModeActive: Bool? = nil,
        hiddenTuningDetected: Bool? = nil,
        safeLockActive: Bool? = nil,
        unboundRebound: Bool? = nil,
        physicalMarks: [String] = [],
        gearMode: Int? = nil,
        gearMax: Int? = nil,
        protocolGen: Int? = nil,
        evidenceSha256: String? = nil,
        rawRegisters: [RawRegister] = [],
        liveBoards: [String] = []
    ) {
        self.serialDisplay = serialDisplay
        self.serialExpected = serialExpected
        self.serialMcu = serialMcu
        self.serialBle = serialBle
        self.serialBms = serialBms
        self.serialVcu = serialVcu
        self.speedCurrentKmh = speedCurrentKmh
        self.speedMaxKmh = speedMaxKmh
        self.speedRatedKmh = speedRatedKmh
        self.speedLimitKmh = speedLimitKmh
        self.peakSpeedKmh = peakSpeedKmh
        self.odometerKm = odometerKm
        self.tripKm = tripKm
        self.remainKm = remainKm
        self.rideTimeMinutes = rideTimeMinutes
        self.totalRideTimeMinutes = totalRideTimeMinutes
        self.chargeCycles = chargeCycles
        self.fwMcu = fwMcu
        self.fwBle = fwBle
        self.fwBms = fwBms
        self.fwVcu = fwVcu
        self.fwEsc = fwEsc
        self.fwAppCustom = fwAppCustom
        self.batteryPercent = batteryPercent
        self.batteryVoltage = batteryVoltage
        self.batteryCurrent = batteryCurrent
        self.batteryHealth = batteryHealth
        self.batteryTempC = batteryTempC
        self.mcuTempC = mcuTempC
        self.motorTempC = motorTempC
        self.errorCode = errorCode
        self.alarmCode = alarmCode
        self.errorActive = errorActive
        self.peakPowerW = peakPowerW
        self.panicModeActive = panicModeActive
        self.hiddenTuningDetected = hiddenTuningDetected
        self.safeLockActive = safeLockActive
        self.unboundRebound = unboundRebound
        self.physicalMarks = physicalMarks
        self.gearMode = gearMode
        self.gearMax = gearMax
        self.protocolGen = protocolGen
        self.evidenceSha256 = evidenceSha256
        self.rawRegisters = rawRegisters
        self.liveBoards = liveBoards
    }
}

// MARK: - Tracks

enum TrackId: String, Codable, CaseIterable, Sendable {
    case stock
    case webapp
    case shu
    case shuDump = "shu_dump"
    case unknown

    var label: String {
        switch self {
        case .stock: return "Serienkonfiguration"
        case .webapp: return "Web-App-Tuning"
        case .shu: return "SHU-Tuning"
        case .shuDump: return "SHU-Dump / Vollauslese"
        case .unknown: return "Nicht klassifiziert"
        }
    }
}

struct TrackMatch: Codable, Hashable, Sendable {
    let trackId: TrackId
    let confidence: Double
    let matchedPatterns: [String]
    let explanation: String

    init(trackId: TrackId, confidence: Double, matchedPatterns: [String], explanation: String = "") {
        self.trackId = trackId
        self.confidence = min(1.0, max(0.0, confidence))
        self.matchedPatterns = matchedPatterns
        self.explanation = explanation
    }
}

// MARK: - Facts & Findings

enum FactGroup: String, Codable, CaseIterable, Sendable {
    case serial = "Seriennummern"
    case speed = "Geschwindigkeit"
    case firmware = "Firmware"
    case odometer = "Kilometerstand"
    case battery = "Batterie"
    case temperature = "Temperatur"
    case error = "Fehler / Alarm"
    case flags = "Sicherheitsflags"
    case protocol = "Protokoll"
    case integrity = "Integrität"
    case physical = "Physische Merkmale"
    case boards = "Steuergeräte"
    case history = "Fahrhistorie"
    case gear = "Fahrmodus"
}

struct MeasuredFact: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let group: FactGroup
    let title: String
    let auslesewert: String
    let sollwert: String
    let status: FactStatus
    let bewertung: String
    let erlaeuterung: String
    let raw: String?

    init(
        id: String,
        group: FactGroup,
        title: String,
        auslesewert: String,
        sollwert: String,
        status: FactStatus,
        bewertung: String,
        erlaeuterung: String,
        raw: String? = nil
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.auslesewert = auslesewert
        self.sollwert = sollwert
        self.status = status
        self.bewertung = bewertung
        self.erlaeuterung = erlaeuterung
        self.raw = raw
    }
}

struct Finding: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let severity: FactStatus
    let title: String
    let detail: String
    let relatedFactIds: [String]
    let trackHint: TrackId?

    init(
        id: String,
        severity: FactStatus,
        title: String,
        detail: String,
        relatedFactIds: [String] = [],
        trackHint: TrackId? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.relatedFactIds = relatedFactIds
        self.trackHint = trackHint
    }
}

// MARK: - Results & Session

struct IntegrityResult: Codable, Hashable, Sendable {
    let sessionId: UUID
    let profile: ScooterProfile
    let reading: IntegrityReading
    let facts: [MeasuredFact]
    let factGroups: [FactGroup: [MeasuredFact]]
    let findings: [Finding]
    let trackMatch: TrackMatch
    let score: Int
    let verdict: VerdictLevel
    let analyzedAt: Date
    let disclaimer: String

    init(
        sessionId: UUID,
        profile: ScooterProfile,
        reading: IntegrityReading,
        facts: [MeasuredFact],
        findings: [Finding],
        trackMatch: TrackMatch,
        score: Int,
        verdict: VerdictLevel,
        analyzedAt: Date = Date(),
        disclaimer: String = IntegrityResult.defaultDisclaimer
    ) {
        self.sessionId = sessionId
        self.profile = profile
        self.reading = reading
        self.facts = facts
        self.factGroups = Dictionary(grouping: facts, by: \.group)
        self.findings = findings
        self.trackMatch = trackMatch
        self.score = min(100, max(0, score))
        self.verdict = verdict
        self.analyzedAt = analyzedAt
        self.disclaimer = disclaimer
    }

    static let defaultDisclaimer = """
    Dieses Protokoll wurde ausschließlich auf Basis einer schreibgeschützten Auslesung erstellt. \
    Es erfolgt keine Veränderung von Fahrzeugparametern. Die Bewertung ersetzt keine amtliche \
    Begutachtung, Typgenehmigungsprüfung oder Sachverständigenbegutachtung im Sinne der \
    Straßenverkehrs-Zulassungs-Ordnung (StVZO).
    """
}

struct CheckSession: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var profile: ScooterProfile
    var reading: IntegrityReading
    var result: IntegrityResult?
    let createdAt: Date
    var protocolNumber: String

    init(
        id: UUID = UUID(),
        profile: ScooterProfile,
        reading: IntegrityReading = IntegrityReading(),
        result: IntegrityResult? = nil,
        createdAt: Date = Date(),
        protocolNumber: String? = nil
    ) {
        self.id = id
        self.profile = profile
        self.reading = reading
        self.result = result
        self.createdAt = createdAt
        self.protocolNumber = protocolNumber ?? CheckSession.makeProtocolNumber(from: createdAt, id: id)
    }

    static func makeProtocolNumber(from date: Date, id: UUID) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "yyyyMMdd"
        let suffix = id.uuidString.prefix(8).uppercased()
        return "SC-\(formatter.string(from: date))-\(suffix)"
    }
}
