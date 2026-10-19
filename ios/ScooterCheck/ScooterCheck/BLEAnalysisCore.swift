import Foundation
import SwiftUI
import CoreLocation
import Combine

// MARK: - Privacy layer types (session-scoped vs validated scooter)

/// Rohes BLE-Gerät aus dem Scan — keine Scooter-Klassifikation.
typealias BLEDevice = ScannedDevice

/// Beobachtetes BLE-Gerät in einer aktiven Multi-/Suchsession (ephemer).
/// Wird niemals automatisch als ValidatedScooter persistiert.
struct ObservedBLEDevice: Identifiable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var fingerprint: BLEDeviceFingerprint
    var rawRssi: Int?
    var smoothedRssi: Double?
    var trend: BLESignalTrend
    var isVisible: Bool
    var lastSeenAt: Date?
    var similarity: BLEFingerprintSimilarity?
    /// Explizit vom Nutzer ausgewählt — nie automatische Scooter-Zuordnung.
    var userSelected: Bool
}

/// Marker-Trennung: validierte Scooter leben in ScooterVerification / KnownScooter.
enum ValidatedScooterBoundary {
    static let note = "Allgemeine BLE-Beobachtung speichert keine Scooter."
}

// MARK: - Fingerprint

enum BLEFingerprintSimilarity: String, Sendable, Codable {
    case high
    case medium
    case low
    case none

    var label: String {
        switch self {
        case .high: return "Hohe Übereinstimmung mit zuvor gesehenem Gerät"
        case .medium: return "Mittlere Übereinstimmung mit zuvor gesehenem Gerät"
        case .low: return "Geringe Übereinstimmung mit zuvor gesehenem Gerät"
        case .none: return "Keine erkennbare Übereinstimmung"
        }
    }

    static func from(score: Int) -> BLEFingerprintSimilarity {
        switch score {
        case 70...: return .high
        case 40..<70: return .medium
        case 15..<40: return .low
        default: return .none
        }
    }
}

struct BLEFingerprintFactor: Identifiable, Equatable, Sendable, Codable {
    var id: String
    var title: String
    var matched: Bool
    var note: String?
}

struct BLEDeviceFingerprint: Equatable, Sendable, Codable {
    var localName: String?
    var manufacturerDataHex: String?
    var manufacturerId: UInt16?
    var serviceUUIDs: [String]
    var serviceDataHexByUUID: [String: String]
    var advertisingStructureKey: String
    var txPower: Int?
    var isConnectable: Bool?
    var observedIntervalMs: Double?
    var capturedAt: Date

    init(
        localName: String? = nil,
        manufacturerDataHex: String? = nil,
        manufacturerId: UInt16? = nil,
        serviceUUIDs: [String] = [],
        serviceDataHexByUUID: [String: String] = [:],
        advertisingStructureKey: String = "",
        txPower: Int? = nil,
        isConnectable: Bool? = nil,
        observedIntervalMs: Double? = nil,
        capturedAt: Date = Date()
    ) {
        self.localName = Self.normalizeName(localName)
        // Compact hex so "4C 00" and "4C00" compare equal — RSSI never part of identity.
        self.manufacturerDataHex = BLEManufacturerParsing.compactHex(manufacturerDataHex)
        self.manufacturerId = manufacturerId
            ?? BLEManufacturerParsing.companyId(fromManufacturerHex: manufacturerDataHex)
        self.serviceUUIDs = serviceUUIDs.map { $0.uppercased() }.sorted()
        self.serviceDataHexByUUID = Dictionary(
            uniqueKeysWithValues: serviceDataHexByUUID.map {
                ($0.key.uppercased(), BLEManufacturerParsing.compactHex($0.value) ?? $0.value.uppercased())
            }
        )
        self.advertisingStructureKey = advertisingStructureKey
        self.txPower = txPower
        self.isConnectable = isConnectable
        self.observedIntervalMs = observedIntervalMs
        self.capturedAt = capturedAt
    }

    static func from(device: ScannedDevice, observedIntervalMs: Double? = nil) -> BLEDeviceFingerprint {
        let mfg = device.manufacturerDataHex
        let mfgId = BLEManufacturerParsing.companyId(fromManufacturerHex: mfg)
        let structure = advertisingStructureKey(
            hasName: !(device.cryptoName.isEmpty),
            hasMfg: mfg != nil,
            serviceCount: device.serviceUUIDs.count,
            hasServiceData: !(device.serviceDataHexByUUID?.isEmpty ?? true),
            hasTx: device.txPower != nil,
            connectable: device.isConnectable
        )
        return BLEDeviceFingerprint(
            localName: device.cryptoName.isEmpty ? nil : device.cryptoName,
            manufacturerDataHex: mfg,
            manufacturerId: mfgId,
            serviceUUIDs: device.serviceUUIDs,
            serviceDataHexByUUID: device.serviceDataHexByUUID ?? [:],
            advertisingStructureKey: structure,
            txPower: device.txPower,
            isConnectable: device.isConnectable,
            observedIntervalMs: observedIntervalMs,
            capturedAt: device.lastSeen
        )
    }

    private static func normalizeName(_ name: String?) -> String? {
        guard let name else { return nil }
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.hasPrefix("Ohne Namen") { return nil }
        return t
    }

    private static func advertisingStructureKey(
        hasName: Bool,
        hasMfg: Bool,
        serviceCount: Int,
        hasServiceData: Bool,
        hasTx: Bool,
        connectable: Bool?
    ) -> String {
        [
            hasName ? "N" : "-",
            hasMfg ? "M" : "-",
            "S\(serviceCount)",
            hasServiceData ? "D" : "-",
            hasTx ? "T" : "-",
            connectable == true ? "C" : (connectable == false ? "c" : "?")
        ].joined()
    }
}

struct BLEFingerprintMatchResult: Equatable, Sendable {
    var score: Int
    var similarity: BLEFingerprintSimilarity
    var factors: [BLEFingerprintFactor]
    var summary: String { similarity.label }
}

enum BLEFingerprintService {
    /// Vergleich konstanter BLE-Merkmale. Name-Änderung allein senkt den Score nicht stark.
    static func compare(_ a: BLEDeviceFingerprint, _ b: BLEDeviceFingerprint) -> BLEFingerprintMatchResult {
        var score = 0
        var maxScore = 0
        var factors: [BLEFingerprintFactor] = []

        func add(_ id: String, _ title: String, weight: Int, matched: Bool, note: String? = nil) {
            maxScore += weight
            if matched { score += weight }
            factors.append(BLEFingerprintFactor(id: id, title: title, matched: matched, note: note))
        }

        let mfgExact = a.manufacturerDataHex != nil
            && a.manufacturerDataHex == b.manufacturerDataHex
        let mfgIdMatch = a.manufacturerId != nil && a.manufacturerId == b.manufacturerId
        add("mfg", "Manufacturer Data stimmt überein", weight: 28, matched: mfgExact,
            note: mfgExact ? nil : (mfgIdMatch ? "nur Manufacturer-ID ähnlich" : "fehlt oder anders"))
        if !mfgExact && mfgIdMatch {
            score += 10
            maxScore += 10
        } else {
            maxScore += 10
        }

        let setA = Set(a.serviceUUIDs)
        let setB = Set(b.serviceUUIDs)
        let uuidMatch = !setA.isEmpty && setA == setB
        let uuidOverlap = !setA.isEmpty && !setB.isEmpty && !setA.isDisjoint(with: setB)
        add("uuid", "identische Service UUIDs", weight: 26, matched: uuidMatch,
            note: uuidMatch ? nil : (uuidOverlap ? "teilweise Überlappung" : "keine gemeinsamen UUIDs"))
        if !uuidMatch && uuidOverlap {
            score += 10
        }

        let structSimilar = !a.advertisingStructureKey.isEmpty
            && a.advertisingStructureKey == b.advertisingStructureKey
        add("adv", "Advertising-Struktur ähnlich", weight: 14, matched: structSimilar)

        let sdA = a.serviceDataHexByUUID
        let sdB = b.serviceDataHexByUUID
        let sdMatch = !sdA.isEmpty && sdA == sdB
        add("sd", "Service Data stimmt überein", weight: 12, matched: sdMatch,
            note: sdA.isEmpty && sdB.isEmpty ? "beide ohne Service Data" : nil)
        if sdA.isEmpty && sdB.isEmpty {
            // Neutral — kein Abzug
            score += 6
        }

        let txMatch = a.txPower != nil && a.txPower == b.txPower
        add("tx", "TX Power gleich", weight: 6, matched: txMatch,
            note: a.txPower == nil && b.txPower == nil ? "beide ohne TX Power" : nil)
        if a.txPower == nil && b.txPower == nil { score += 3 }

        let connMatch = a.isConnectable != nil && a.isConnectable == b.isConnectable
        add("conn", "Connectable-Flag gleich", weight: 6, matched: connMatch)

        let nameA = a.localName
        let nameB = b.localName
        if let nameA, let nameB {
            let same = nameA.caseInsensitiveCompare(nameB) == .orderedSame
            add("name", same ? "Gerätename identisch" : "Gerätename geändert", weight: 8, matched: same,
                note: same ? nil : "Name allein ist kein Ausschlusskriterium")
        } else if nameA == nil && nameB == nil {
            add("name", "kein Gerätename (beide)", weight: 4, matched: true)
        } else {
            add("name", "Gerätename nur auf einer Seite", weight: 4, matched: false,
                note: "leerer/geänderter Name ist erlaubt")
        }

        let pct = maxScore > 0 ? Int((Double(score) / Double(maxScore) * 100).rounded()) : 0
        let clamped = min(100, max(0, pct))
        return BLEFingerprintMatchResult(
            score: clamped,
            similarity: .from(score: clamped),
            factors: factors
        )
    }
}

// MARK: - Timeline

enum BLESearchEventType: String, Sendable, Codable, CaseIterable {
    case searchStarted
    case deviceFirstSeen
    case signalStronger
    case strongestAreaUpdated
    case signalLost
    case signalRefound
    case signalPossiblyRefound
    case advertisingChanged
    case devicePossiblyMoved
    case coarseMode
    case fineMode
    case deviceConnected
    case connectionFailed
    case searchEnded
}

struct BLESearchEvent: Identifiable, Equatable, Sendable, Codable {
    var id: UUID
    var timestamp: Date
    var type: BLESearchEventType
    var title: String
    var description: String?
    var rssi: Double?
    var latitude: Double?
    var longitude: Double?
    var metadata: [String: String]?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: BLESearchEventType,
        title: String,
        description: String? = nil,
        rssi: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.description = description
        self.rssi = rssi
        self.latitude = latitude
        self.longitude = longitude
        self.metadata = metadata
    }
}

struct BLESearchTimeline: Equatable, Sendable {
    private(set) var events: [BLESearchEvent] = []
    private var lastTypeAt: [BLESearchEventType: Date] = [:]

    mutating func reset() {
        events = []
        lastTypeAt = [:]
    }

    /// Nur relevante Zustandsänderungen — mit Debounce je Typ.
    @discardableResult
    mutating func append(
        _ event: BLESearchEvent,
        minInterval: TimeInterval = 1.2
    ) -> Bool {
        if let last = lastTypeAt[event.type],
           event.timestamp.timeIntervalSince(last) < minInterval,
           event.type != .searchStarted,
           event.type != .searchEnded,
           event.type != .deviceFirstSeen {
            return false
        }
        events.append(event)
        lastTypeAt[event.type] = event.timestamp
        if events.count > 200 {
            events.removeFirst(events.count - 200)
        }
        return true
    }

    var chronological: [BLESearchEvent] {
        events.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Signal history (graph)

enum BLESignalHistoryMarkerKind: String, Sendable {
    case signalLost
    case signalRefound
    case strongest
}

struct BLESignalHistoryMarker: Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var kind: BLESignalHistoryMarkerKind
}

struct BLESignalHistoryPoint: Equatable, Sendable {
    var timestamp: Date
    var smoothed: Double
    var raw: Int?
}

struct BLESignalHistory: Equatable, Sendable {
    private(set) var points: [BLESignalHistoryPoint] = []
    private(set) var markers: [BLESignalHistoryMarker] = []
    var windowSeconds: TimeInterval = 45

    mutating func reset() {
        points = []
        markers = []
    }

    mutating func append(smoothed: Double, raw: Int?, at date: Date = Date()) {
        points.append(BLESignalHistoryPoint(timestamp: date, smoothed: smoothed, raw: raw))
        // Aggregation: bei hoher Frequenz ältere Punkte ausdünnen
        if points.count > 240 {
            points = downsample(points, target: 160)
        }
        let cutoff = date.addingTimeInterval(-windowSeconds)
        points.removeAll { $0.timestamp < cutoff }
        markers.removeAll { $0.timestamp < cutoff }
    }

    mutating func addMarker(_ kind: BLESignalHistoryMarkerKind, at date: Date = Date()) {
        markers.append(BLESignalHistoryMarker(id: UUID(), timestamp: date, kind: kind))
        if markers.count > 40 {
            markers.removeFirst(markers.count - 40)
        }
    }

    private func downsample(_ src: [BLESignalHistoryPoint], target: Int) -> [BLESignalHistoryPoint] {
        guard src.count > target else { return src }
        let step = Double(src.count) / Double(target)
        var out: [BLESignalHistoryPoint] = []
        var i = 0.0
        while Int(i) < src.count && out.count < target {
            out.append(src[Int(i)])
            i += step
        }
        if let last = src.last, out.last?.timestamp != last.timestamp {
            out.append(last)
        }
        return out
    }
}

// MARK: - Movement analyzer

enum BLEMovementHintConfidence: String, Sendable, Codable {
    case weak
    case medium
    case strong

    var label: String {
        switch self {
        case .weak: return "schwacher Hinweis"
        case .medium: return "mittlerer Hinweis"
        case .strong: return "starker Hinweis"
        }
    }
}

struct BLEMovementHint: Equatable, Sendable {
    var active: Bool
    var confidence: BLEMovementHintConfidence
    var explanation: String

    static let inactive = BLEMovementHint(
        active: false,
        confidence: .weak,
        explanation: ""
    )
}

struct BLEMovementAnalyzer: Equatable, Sendable {
    /// Mindestdauer einer konsistenten RSSI-Veränderung bei stillstehendem Handy.
    static let minDuration: TimeInterval = 12
    static let phoneStillSpeedMax: Double = 0.35 // m/s
    static let phoneStillAccuracyMax: Double = 25
    static let rssiDeltaThreshold: Double = 8.0
    static let minSamples = 6

    private var phoneStillSince: Date?
    private var baselineRssi: Double?
    private var consistentChangeSince: Date?
    private var lastHintAt: Date?

    mutating func reset() {
        phoneStillSince = nil
        baselineRssi = nil
        consistentChangeSince = nil
        lastHintAt = nil
    }

    mutating func evaluate(
        now: Date,
        phoneSpeed: Double?,
        accuracy: Double?,
        smoothedRssi: Double?,
        signalLostRecently: Bool,
        heatmapCentroidShiftMeters: Double?
    ) -> BLEMovementHint {
        let phoneStill: Bool = {
            guard let speed = phoneSpeed, speed >= 0, speed <= Self.phoneStillSpeedMax else { return false }
            if let a = accuracy, a > Self.phoneStillAccuracyMax { return false }
            return true
        }()

        if phoneStill {
            if phoneStillSince == nil { phoneStillSince = now }
        } else {
            phoneStillSince = nil
            baselineRssi = smoothedRssi
            consistentChangeSince = nil
            return .inactive
        }

        guard let stillSince = phoneStillSince,
              now.timeIntervalSince(stillSince) >= 4,
              let rssi = smoothedRssi else {
            return .inactive
        }

        if baselineRssi == nil { baselineRssi = rssi }
        let delta = abs(rssi - (baselineRssi ?? rssi))
        let strongShift = delta >= Self.rssiDeltaThreshold
            || (signalLostRecently && delta >= Self.rssiDeltaThreshold * 0.7)
            || (heatmapCentroidShiftMeters ?? 0) >= 4.0

        if strongShift {
            if consistentChangeSince == nil { consistentChangeSince = now }
        } else {
            consistentChangeSince = nil
            // langsame Drift der Baseline
            baselineRssi = ScooterFinderMath.ema(previous: baselineRssi, sample: rssi, alpha: 0.08)
        }

        guard let changeSince = consistentChangeSince,
              now.timeIntervalSince(changeSince) >= Self.minDuration else {
            return .inactive
        }

        // Debounce UI
        if let last = lastHintAt, now.timeIntervalSince(last) < 8 {
            return BLEMovementHint(
                active: true,
                confidence: confidence(for: delta, centroid: heatmapCentroidShiftMeters),
                explanation: "Das Signal verändert sich deutlich, obwohl sich das Smartphone kaum bewegt."
            )
        }
        lastHintAt = now

        return BLEMovementHint(
            active: true,
            confidence: confidence(for: delta, centroid: heatmapCentroidShiftMeters),
            explanation: "Das Signal verändert sich deutlich, obwohl sich das Smartphone kaum bewegt."
        )
    }

    private func confidence(for delta: Double, centroid: Double?) -> BLEMovementHintConfidence {
        let c = centroid ?? 0
        if delta >= 14 || c >= 8 { return .strong }
        if delta >= 10 || c >= 5 { return .medium }
        return .weak
    }
}

// MARK: - Best movement direction (not a BLE compass)

struct BLEDirectionTrend: Equatable, Sendable {
    var headingDegrees: Double?
    var label: String
    var detail: String
    var reliable: Bool

    static let none = BLEDirectionTrend(
        headingDegrees: nil,
        label: "Noch keine verlässliche Bewegungsrichtung",
        detail: "Bewege dich, bis ein klarer Signaltrend erkennbar ist.",
        reliable: false
    )
}

struct BLEDirectionTrendService: Sendable {
    static let minPathMeters: Double = 3.5
    static let minRssiGain: Double = 4.0
    static let minSegmentSeconds: TimeInterval = 4.0

    private var samples: [(date: Date, x: Double, y: Double, rssi: Double)] = []
    private var lastReliable: BLEDirectionTrend = .none

    mutating func reset() {
        samples = []
        lastReliable = .none
    }

    mutating func ingest(date: Date, x: Double, y: Double, rssi: Double) {
        samples.append((date, x, y, rssi))
        if samples.count > 80 {
            samples.removeFirst(samples.count - 80)
        }
        let cutoff = date.addingTimeInterval(-45)
        samples.removeAll { $0.date < cutoff }
    }

    mutating func evaluate(at date: Date = Date()) -> BLEDirectionTrend {
        let recent = samples.filter { date.timeIntervalSince($0.date) <= 28 }
        guard recent.count >= 5 else { return lastReliable.reliable ? lastReliable : .none }

        let first = recent.first!
        let last = recent.last!
        let dx = last.x - first.x
        let dy = last.y - first.y
        let dist = hypot(dx, dy)
        let dt = last.date.timeIntervalSince(first.date)
        guard dist >= Self.minPathMeters, dt >= Self.minSegmentSeconds else {
            return lastReliable.reliable ? lastReliable : .none
        }

        let mid = recent.count / 2
        let early = recent.prefix(max(2, mid)).map(\.rssi)
        let late = recent.suffix(max(2, recent.count - mid)).map(\.rssi)
        let earlyAvg = early.reduce(0, +) / Double(early.count)
        let lateAvg = late.reduce(0, +) / Double(late.count)
        let gain = lateAvg - earlyAvg
        guard gain >= Self.minRssiGain else {
            return .none
        }

        // Heading: 0 = Nord, Uhrzeigersinn; relative ENU: x=East, y=North
        var deg = atan2(dx, dy) * 180 / .pi
        if deg < 0 { deg += 360 }
        let trend = BLEDirectionTrend(
            headingDegrees: deg,
            label: "Beste Bewegungsrichtung zuletzt",
            detail: "In dieser Bewegungsrichtung wurde das Signal stärker.",
            reliable: true
        )
        lastReliable = trend
        return trend
    }
}

// MARK: - Search grid / area coverage

enum BLESearchGridCellStatus: String, Sendable, Codable {
    case unscanned
    case partial
    case scanned
}

struct BLESearchGridCell: Equatable, Sendable {
    var sampleCount: Int = 0
    var lastSampleAt: Date?
    var avgSmoothedRssi: Double?
    var density: Double = 0
    var bestQuality: BLEPositionQuality = .unknown

    var status: BLESearchGridCellStatus {
        if sampleCount <= 0 { return .unscanned }
        if sampleCount >= 3, density >= 0.55, bestQuality != .low && bestQuality != .unknown {
            return .scanned
        }
        return .partial
    }
}

enum BLESearchAreaKind: String, Sendable, Codable {
    case autoFromPath
    case userRect
    case userCircle
    case userPolygon
}

struct BLESearchArea: Equatable, Sendable {
    var kind: BLESearchAreaKind
    /// Relative ENU bounds (meters).
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
    /// Optional circle (userCircle).
    var centerX: Double?
    var centerY: Double?
    var radius: Double?
    /// Optional polygon vertices (userPolygon) — Architektur vorbereitet.
    var polygon: [(x: Double, y: Double)]?

    var width: Double { max(0, maxX - minX) }
    var height: Double { max(0, maxY - minY) }
    var isMeaningful: Bool {
        width >= 6 && height >= 6 && width * height >= 80
    }

    static func == (lhs: BLESearchArea, rhs: BLESearchArea) -> Bool {
        guard lhs.kind == rhs.kind,
              lhs.minX == rhs.minX, lhs.maxX == rhs.maxX,
              lhs.minY == rhs.minY, lhs.maxY == rhs.maxY,
              lhs.centerX == rhs.centerX, lhs.centerY == rhs.centerY,
              lhs.radius == rhs.radius else { return false }
        switch (lhs.polygon, rhs.polygon) {
        case (nil, nil): return true
        case let (l?, r?):
            guard l.count == r.count else { return false }
            for i in l.indices where l[i].x != r[i].x || l[i].y != r[i].y { return false }
            return true
        default: return false
        }
    }

    func contains(x: Double, y: Double) -> Bool {
        switch kind {
        case .userCircle:
            guard let cx = centerX, let cy = centerY, let r = radius else {
                return x >= minX && x <= maxX && y >= minY && y <= maxY
            }
            return hypot(x - cx, y - cy) <= r
        case .userPolygon:
            guard let poly = polygon, poly.count >= 3 else {
                return x >= minX && x <= maxX && y >= minY && y <= maxY
            }
            return pointInPolygon(x: x, y: y, poly: poly)
        default:
            return x >= minX && x <= maxX && y >= minY && y <= maxY
        }
    }

    private func pointInPolygon(x: Double, y: Double, poly: [(x: Double, y: Double)]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let xi = poly[i].x, yi = poly[i].y
            let xj = poly[j].x, yj = poly[j].y
            let intersect = ((yi > y) != (yj > y))
                && (x < (xj - xi) * (y - yi) / max(yj - yi, 1e-9) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    static func autoFrom(measurements: [BLEMeasurement], padding: Double = 4) -> BLESearchArea? {
        let pts = measurements.compactMap { m -> (Double, Double)? in
            guard let x = m.relativeX, let y = m.relativeY else { return nil }
            return (x, y)
        }
        guard pts.count >= 4 else { return nil }
        let xs = pts.map(\.0)
        let ys = pts.map(\.1)
        let minX = (xs.min() ?? 0) - padding
        let maxX = (xs.max() ?? 0) + padding
        let minY = (ys.min() ?? 0) - padding
        let maxY = (ys.max() ?? 0) + padding
        let area = BLESearchArea(
            kind: .autoFromPath,
            minX: minX, maxX: maxX, minY: minY, maxY: maxY
        )
        return area.isMeaningful ? area : nil
    }
}

struct BLESearchGrid: Equatable, Sendable {
    var cellSize: Double = 2.5
    var cols: Int = 0
    var rows: Int = 0
    var originX: Double = 0
    var originY: Double = 0
    var cells: [BLESearchGridCell] = []
    var area: BLESearchArea?
    /// 0…1 — nur sinnvoll wenn area definiert und meaningful.
    var coverageRatio: Double?

    var coveragePercentText: String? {
        guard let r = coverageRatio, area?.isMeaningful == true else { return nil }
        return String(format: "Suchfläche zu %.0f %% untersucht", r * 100)
    }

    static let empty = BLESearchGrid()

    static func build(
        from measurements: [BLEMeasurement],
        userArea: BLESearchArea? = nil
    ) -> BLESearchGrid {
        let area = userArea ?? BLESearchArea.autoFrom(measurements: measurements)
        guard let area, area.isMeaningful else {
            return .empty
        }
        let cell = 2.5
        let cols = max(1, Int(ceil(area.width / cell)))
        let rows = max(1, Int(ceil(area.height / cell)))
        var cells = Array(repeating: BLESearchGridCell(), count: cols * rows)
        let plotted = measurements.compactMap { m -> (Double, Double, Double, BLEPositionQuality)? in
            guard let x = m.relativeX, let y = m.relativeY, area.contains(x: x, y: y) else { return nil }
            return (x, y, m.smoothedRssi, m.quality)
        }
        for p in plotted {
            let c = Int(((p.0 - area.minX) / cell).rounded(.down))
            let r = Int(((p.1 - area.minY) / cell).rounded(.down))
            guard c >= 0, c < cols, r >= 0, r < rows else { continue }
            let idx = r * cols + c
            var cellState = cells[idx]
            let n = Double(cellState.sampleCount)
            cellState.avgSmoothedRssi = cellState.avgSmoothedRssi.map { ($0 * n + p.2) / (n + 1) } ?? p.2
            cellState.sampleCount += 1
            cellState.lastSampleAt = Date()
            cellState.density = min(1.0, Double(cellState.sampleCount) / 4.0)
            if p.3.weight >= cellState.bestQuality.weight {
                cellState.bestQuality = p.3
            }
            cells[idx] = cellState
        }

        // Coverage: nur Zellen, die im Area-Rechteck liegen und (bei Kreis/Polygon) Treffer erlauben
        var eligible = 0
        var covered = 0
        for r in 0..<rows {
            for c in 0..<cols {
                let cx = area.minX + (Double(c) + 0.5) * cell
                let cy = area.minY + (Double(r) + 0.5) * cell
                guard area.contains(x: cx, y: cy) else { continue }
                eligible += 1
                let status = cells[r * cols + c].status
                if status == .scanned { covered += 1 }
                else if status == .partial { covered += 1 /* halb in Ratio unten */ }
            }
        }
        // PARTIAL zählt 0.45, SCANNED 1.0
        var score = 0.0
        for r in 0..<rows {
            for c in 0..<cols {
                let cx = area.minX + (Double(c) + 0.5) * cell
                let cy = area.minY + (Double(r) + 0.5) * cell
                guard area.contains(x: cx, y: cy) else { continue }
                switch cells[r * cols + c].status {
                case .scanned: score += 1
                case .partial: score += 0.45
                case .unscanned: break
                }
            }
        }
        let ratio = eligible > 0 ? min(1, score / Double(eligible)) : nil

        return BLESearchGrid(
            cellSize: cell,
            cols: cols,
            rows: rows,
            originX: area.minX,
            originY: area.minY,
            cells: cells,
            area: area,
            coverageRatio: ratio
        )
    }
}

// MARK: - Multi-device monitor

@MainActor
final class BLEMultiDeviceMonitor: ObservableObject {
    static let minDevices = 1
    static let maxDevices = 5

    @Published private(set) var observed: [ObservedBLEDevice] = []
    @Published private(set) var isActive = false

    private var processors: [UUID: BLESignalProcessor] = [:]
    private var fingerprints: [UUID: BLEDeviceFingerprint] = [:]
    private var lastSeen: [UUID: Date] = [:]
    private var lastAdvFingerprintCheck: [UUID: Date] = [:]
    private weak var ble: BleClient?
    private var cancellable: AnyCancellable?
    private var tickTimer: Timer?
    private var lastUIPublish = Date.distantPast

    func start(devices: [ScannedDevice], ble: BleClient) {
        stop()
        let picked = Array(devices.prefix(Self.maxDevices))
        guard !picked.isEmpty else { return }
        self.ble = ble
        isActive = true
        observed = picked.map { d in
            let fp = BLEDeviceFingerprint.from(device: d)
            fingerprints[d.id] = fp
            processors[d.id] = BLESignalProcessor()
            lastSeen[d.id] = d.lastSeen
            return ObservedBLEDevice(
                id: d.id,
                displayName: d.bleListDisplayName,
                fingerprint: fp,
                rawRssi: d.rssi,
                smoothedRssi: nil,
                trend: .stable,
                isVisible: true,
                lastSeenAt: d.lastSeen,
                similarity: nil,
                userSelected: true
            )
        }
        cancellable = ble.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] list in
                self?.ingest(list)
            }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        ingest(ble.devices)
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        cancellable?.cancel()
        cancellable = nil
        ble = nil
        isActive = false
        observed = []
        processors = [:]
        fingerprints = [:]
        lastSeen = [:]
        lastAdvFingerprintCheck = [:]
    }

    /// Explizite Auswahl — keine automatische Scooter-Persistenz.
    func replaceSelection(devices: [ScannedDevice], ble: BleClient) {
        start(devices: devices, ble: ble)
    }

    private func ingest(_ devices: [ScannedDevice]) {
        guard isActive else { return }
        let now = Date()
        // Throttle UI publishes
        let shouldPublish = now.timeIntervalSince(lastUIPublish) >= 0.35
        var next = observed
        for i in next.indices {
            let id = next[i].id
            if let device = devices.first(where: { $0.id == id }) {
                lastSeen[id] = device.lastSeen
                next[i].rawRssi = device.rssi
                next[i].isVisible = true
                next[i].lastSeenAt = device.lastSeen
                next[i].displayName = device.bleListDisplayName
                var proc = processors[id] ?? BLESignalProcessor()
                if let s = proc.ingest(rawRssi: device.rssi, at: now) {
                    next[i].smoothedRssi = s
                }
                next[i].trend = proc.trend(at: now)
                processors[id] = proc

                // Fingerprint-Vergleich gedrosselt
                let lastCheck = lastAdvFingerprintCheck[id] ?? .distantPast
                if now.timeIntervalSince(lastCheck) >= 2.5, let baseline = fingerprints[id] {
                    lastAdvFingerprintCheck[id] = now
                    let current = BLEDeviceFingerprint.from(device: device)
                    next[i].fingerprint = current
                    next[i].similarity = BLEFingerprintService.compare(baseline, current).similarity
                }
            } else {
                let since = lastSeen[id].map { now.timeIntervalSince($0) } ?? 999
                next[i].isVisible = since < BLESignalConfig.signalLostSoftSeconds
                if since >= BLESignalConfig.signalLostSoftSeconds {
                    next[i].rawRssi = nil
                }
            }
        }
        if shouldPublish {
            observed = next
            lastUIPublish = now
        } else {
            // still update internal state without forcing SwiftUI if identical visibility
            observed = next
        }
    }

    private func tick() {
        guard isActive else { return }
        ingest(ble?.devices ?? [])
    }
}
