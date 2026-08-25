import Foundation

// MARK: - Scooter Profile

/// Marktvariante: DE/L1e-B 20 km/h vs. EU 25 km/h.
enum ScooterMarket: String, Codable, Sendable {
    case de20
    case eu25

    var ratedMaxKmh: Double { self == .de20 ? 20 : 25 }
    var tuningSuspectKmh: Double { self == .de20 ? 22 : 27 }
    var tuningClearKmh: Double { self == .de20 ? 25 : 32 }
}

enum ScooterFamily: String, CaseIterable, Codable, Sendable {
    case zt3Pro
    case maxG30
    case ninebotF
    case ninebotD
    case xiaomiClassic
    case xiaomiRecent

    var title: String {
        switch self {
        case .zt3Pro: return "Ninebot ZT3 Pro"
        case .maxG30: return "Ninebot Max G30"
        case .ninebotF: return "Ninebot F-Serie"
        case .ninebotD: return "Ninebot D-Serie"
        case .xiaomiClassic: return "Xiaomi M365 / Pro 2"
        case .xiaomiRecent: return "Xiaomi Scooter 3 / 4"
        }
    }
}

enum ScooterProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case zt3ProD
    case zt3ProE
    case maxG30D
    case maxG30E
    case ninebotFD
    case ninebotFE
    case ninebotDD
    case ninebotDE
    case xiaomiClassicD
    case xiaomiClassicE
    case xiaomiRecentD
    case xiaomiRecentE

    var id: String { rawValue }

    var family: ScooterFamily {
        switch self {
        case .zt3ProD, .zt3ProE: return .zt3Pro
        case .maxG30D, .maxG30E: return .maxG30
        case .ninebotFD, .ninebotFE: return .ninebotF
        case .ninebotDD, .ninebotDE: return .ninebotD
        case .xiaomiClassicD, .xiaomiClassicE: return .xiaomiClassic
        case .xiaomiRecentD, .xiaomiRecentE: return .xiaomiRecent
        }
    }

    var market: ScooterMarket {
        switch self {
        case .zt3ProD, .maxG30D, .ninebotFD, .ninebotDD, .xiaomiClassicD, .xiaomiRecentD:
            return .de20
        case .zt3ProE, .maxG30E, .ninebotFE, .ninebotDE, .xiaomiClassicE, .xiaomiRecentE:
            return .eu25
        }
    }

    var label: String {
        "\(family.title) (\(Int(ratedMaxKmh)) km/h)"
    }

    var shortLabel: String {
        switch self {
        case .zt3ProD: return "ZT3 Pro D"
        case .zt3ProE: return "ZT3 Pro E"
        case .maxG30D: return "Max G30D"
        case .maxG30E: return "Max G30E"
        case .ninebotFD: return "F-Serie D"
        case .ninebotFE: return "F-Serie E"
        case .ninebotDD: return "D-Serie D"
        case .ninebotDE: return "D-Serie E"
        case .xiaomiClassicD: return "Xiaomi Classic D"
        case .xiaomiClassicE: return "Xiaomi Classic E"
        case .xiaomiRecentD: return "Xiaomi 3/4 D"
        case .xiaomiRecentE: return "Xiaomi 3/4 E"
        }
    }

    var ratedMaxKmh: Double { market.ratedMaxKmh }
    var tuningSuspectKmh: Double { market.tuningSuspectKmh }
    var tuningClearKmh: Double { market.tuningClearKmh }

    /// Typische Seriennummer-Präfixe für werkseitige Zuordnung.
    var stockSerialHints: [String] {
        switch self {
        case .zt3ProD: return ["N2DT", "N2D"]
        case .zt3ProE: return ["N2ET", "N2E"]
        case .maxG30D: return ["N4GSD", "N4GS", "N4G"]
        case .maxG30E: return ["N4GSE", "N4GS", "N4G"]
        case .ninebotFD: return ["N2FS", "N2F", "F2"]
        case .ninebotFE: return ["N2FS", "N2F", "F2"]
        case .ninebotDD: return ["N2DS", "N2D8", "D18", "D28", "D38"]
        case .ninebotDE: return ["N2DS", "N2D8", "D18", "D28", "D38"]
        case .xiaomiClassicD, .xiaomiClassicE:
            return ["16159", "25708", "M365", "PRO2", "1S"]
        case .xiaomiRecentD, .xiaomiRecentE:
            return ["MI3", "MI4", "XIAOMI"]
        }
    }

    /// BLE-Auslese nutzt derzeit Ninebot Enc2; Xiaomi ggf. nur eingeschränkt.
    var usesNinebotEnc2: Bool {
        switch family {
        case .zt3Pro, .maxG30, .ninebotF, .ninebotD: return true
        case .xiaomiClassic, .xiaomiRecent: return false
        }
    }

    var legalText: String {
        let speedNote = market == .de20
            ? "bauartbedingte Höchstgeschwindigkeit 20 km/h (DE / L1e-B)"
            : "bauartbedingte Höchstgeschwindigkeit 25 km/h (EU)"
        return """
        Soll-Profil für \(family.title) mit \(speedNote). \
        Abweichungen von werkseitigen Parametern können Betriebserlaubnis und \
        Versicherungsschutz beeinträchtigen. Die App liest nur Diagnosedaten und \
        verändert keine Fahrzeugparameter.
        """
    }

    static func profiles(in family: ScooterFamily) -> [ScooterProfile] {
        allCases.filter { $0.family == family }
    }

    /// Grobe Zuordnung aus Bluetooth-Namen / SN-Präfix (nur Vorschlag).
    static func suggested(fromBluetoothName name: String?, serial: String? = nil) -> ScooterProfile? {
        let hay = [name, serial]
            .compactMap { $0?.uppercased() }
            .joined(separator: " ")
        guard !hay.isEmpty else { return nil }

        if hay.contains("ZT3") || hay.hasPrefix("N2DT") || hay.hasPrefix("N2ET") {
            return hay.contains("N2E") || hay.contains("25") ? .zt3ProE : .zt3ProD
        }
        if hay.contains("MAX") || hay.contains("G30") || hay.contains("N4GS") {
            return hay.contains("G30E") || hay.contains("N4GSE") ? .maxG30E : .maxG30D
        }
        if hay.contains("F2") || hay.range(of: #"\bF[234]0\b"#, options: .regularExpression) != nil {
            return hay.contains("F25") || hay.contains("25") ? .ninebotFE : .ninebotFD
        }
        if hay.contains("D18") || hay.contains("D28") || hay.contains("D38") || hay.contains("D-SERIES") {
            return .ninebotDD
        }
        if hay.contains("PRO 2") || hay.contains("PRO2") || hay.contains("M365")
            || hay.contains("1S") || hay.contains("ESSENTIAL") {
            return .xiaomiClassicD
        }
        if hay.contains("SCOOTER 3") || hay.contains("SCOOTER 4") || hay.contains("MI3") || hay.contains("MI4") {
            return .xiaomiRecentD
        }
        return nil
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
    case proto = "Protokoll"
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
