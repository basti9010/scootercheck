import Foundation
import SwiftUI

// MARK: - Config

/// Zentrale BLE-Signal-Schwellwerte — keine Magic Numbers in der UI.
enum BLESignalConfig {
    /// Medianfenster vor EMA.
    static let medianWindow = 7
    /// EMA nach Median (höher = reaktiver).
    static let emaAlpha = 0.32
    /// Trend: Vergleich aktuelles vs. vorheriges geglättetes Fenster (dBm).
    static let trendStrongerDelta = 3.5
    static let trendWeakerDelta = -3.5
    static let trendWindowSeconds: TimeInterval = 2.4

    /// Signal verloren: kurz / länger.
    static let signalLostSoftSeconds: TimeInterval = 3.0
    static let signalLostHardSeconds: TimeInterval = 10.0

    /// Sampling für räumliche Messpunkte.
    static let minSampleInterval: TimeInterval = 0.55
    static let minMoveMeters: Double = 0.55
    static let minRssiChangeForSample: Double = 2.5
    static let maxStoredMeasurements = 900

    /// Heatmap-Raster (Meter im lokalen ENU).
    static let cellSizeMeters: Double = 2.2
    static let paintRadiusMeters: Double = 4.5
    static let maxExtrapolationMeters: Double = 5.5
    static let heatmapCols = 48
    static let heatmapRows = 48

    /// Positionsqualität (horizontale Genauigkeit in m).
    static let accuracyHighMax: Double = 12
    static let accuracyMediumMax: Double = 28

    /// Relative Klassen (gegättetes RSSI, dBm). Stärker = weniger negativ.
    static let veryStrongMin: Double = -50
    static let strongMin: Double = -58
    static let mediumMin: Double = -70
    static let weakMin: Double = -82
    // darunter: veryWeak; kein Signal: lost
}

// MARK: - Classes / Trend

enum BLESignalClass: String, Sendable, CaseIterable {
    case veryStrong
    case strong
    case medium
    case weak
    case veryWeak
    case lost

    var label: String {
        switch self {
        case .veryStrong: return "Sehr stark"
        case .strong: return "Stark"
        case .medium: return "Mittel"
        case .weak: return "Schwach"
        case .veryWeak: return "Sehr schwach"
        case .lost: return "Signal verloren"
        }
    }

    /// 0…1 für Balken (lost = 0).
    var barLevel: Double {
        switch self {
        case .veryStrong: return 1.0
        case .strong: return 0.82
        case .medium: return 0.58
        case .weak: return 0.34
        case .veryWeak: return 0.16
        case .lost: return 0
        }
    }

    static func from(smoothedRssi: Double?, lost: Bool) -> BLESignalClass {
        if lost { return .lost }
        guard let rssi = smoothedRssi else { return .lost }
        switch rssi {
        case BLESignalConfig.veryStrongMin...: return .veryStrong
        case BLESignalConfig.strongMin..<BLESignalConfig.veryStrongMin: return .strong
        case BLESignalConfig.mediumMin..<BLESignalConfig.strongMin: return .medium
        case BLESignalConfig.weakMin..<BLESignalConfig.mediumMin: return .weak
        default: return .veryWeak
        }
    }
}

enum BLESignalTrend: String, Sendable {
    case stronger
    case stable
    case weaker

    var label: String {
        switch self {
        case .stronger: return "wird stärker"
        case .stable: return "stabil"
        case .weaker: return "wird schwächer"
        }
    }

    var symbol: String {
        switch self {
        case .stronger: return "arrow.up"
        case .stable: return "arrow.left.and.right"
        case .weaker: return "arrow.down"
        }
    }

    var warmColdLabel: String {
        switch self {
        case .stronger: return "wärmer"
        case .stable: return "stabil"
        case .weaker: return "kälter"
        }
    }
}

enum BLEPositionQuality: String, Sendable {
    case high
    case medium
    case low
    case unknown

    var label: String {
        switch self {
        case .high: return "gut"
        case .medium: return "mittel"
        case .low: return "eingeschränkt"
        case .unknown: return "unbekannt"
        }
    }

    /// Gewicht für Heatmap-Aggregation.
    var weight: Double {
        switch self {
        case .high: return 1.0
        case .medium: return 0.55
        case .low: return 0.22
        case .unknown: return 0.12
        }
    }

    static func from(accuracyMeters: Double?) -> BLEPositionQuality {
        guard let a = accuracyMeters, a >= 0, a < 500 else { return .unknown }
        if a <= BLESignalConfig.accuracyHighMax { return .high }
        if a <= BLESignalConfig.accuracyMediumMax { return .medium }
        return .low
    }
}

enum BLESearchModeKind: String, Sendable {
    case coarse
    case fine
}

// MARK: - Processor

struct BLESignalProcessor: Sendable {
    private(set) var rawHistory: [Int] = []
    private(set) var smoothed: Double?
    private(set) var smoothedTimeline: [(Date, Double)] = []

    mutating func reset() {
        rawHistory = []
        smoothed = nil
        smoothedTimeline = []
    }

    mutating func ingest(rawRssi: Int, at date: Date = Date()) -> Double? {
        guard rawRssi < 20, rawRssi > -120 else { return smoothed }
        rawHistory.append(rawRssi)
        if rawHistory.count > 48 {
            rawHistory.removeFirst(rawHistory.count - 48)
        }
        let window = Array(rawHistory.suffix(BLESignalConfig.medianWindow)).map(Double.init)
        guard let med = ScooterFinderMath.median(window) else { return smoothed }
        let last = window.last ?? med
        let next = ScooterFinderMath.ema(previous: med, sample: last, alpha: BLESignalConfig.emaAlpha)
        // Zweite EMA gegen bisherigen geglätteten Wert → ruhiger.
        smoothed = ScooterFinderMath.ema(previous: smoothed, sample: next, alpha: BLESignalConfig.emaAlpha)
        if let s = smoothed {
            smoothedTimeline.append((date, s))
            let cutoff = date.addingTimeInterval(-60)
            smoothedTimeline.removeAll { $0.0 < cutoff }
        }
        return smoothed
    }

    func trend(at date: Date = Date()) -> BLESignalTrend {
        let window = BLESignalConfig.trendWindowSeconds
        let recent = smoothedTimeline.filter { $0.0 >= date.addingTimeInterval(-window) }
        let previous = smoothedTimeline.filter {
            $0.0 >= date.addingTimeInterval(-window * 2) && $0.0 < date.addingTimeInterval(-window)
        }
        guard !recent.isEmpty, !previous.isEmpty else { return .stable }
        let rAvg = recent.map(\.1).reduce(0, +) / Double(recent.count)
        let pAvg = previous.map(\.1).reduce(0, +) / Double(previous.count)
        let delta = rAvg - pAvg
        if delta >= BLESignalConfig.trendStrongerDelta { return .stronger }
        if delta <= BLESignalConfig.trendWeakerDelta { return .weaker }
        return .stable
    }
}

// MARK: - Measurement / Session

struct BLEMeasurement: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var rawRssi: Int
    var smoothedRssi: Double
    var latitude: Double?
    var longitude: Double?
    var relativeX: Double?
    var relativeY: Double?
    var accuracy: Double?
    var heading: Double?
    var motionConfidence: Double?
    var positionQuality: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        rawRssi: Int,
        smoothedRssi: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        relativeX: Double? = nil,
        relativeY: Double? = nil,
        accuracy: Double? = nil,
        heading: Double? = nil,
        motionConfidence: Double? = nil,
        positionQuality: BLEPositionQuality
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawRssi = rawRssi
        self.smoothedRssi = smoothedRssi
        self.latitude = latitude
        self.longitude = longitude
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.accuracy = accuracy
        self.heading = heading
        self.motionConfidence = motionConfidence
        self.positionQuality = positionQuality.rawValue
    }

    var quality: BLEPositionQuality {
        BLEPositionQuality(rawValue: positionQuality) ?? .unknown
    }
}

struct BLESearchSession: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var deviceId: UUID
    var deviceName: String
    var startedAt: Date
    var endedAt: Date?
    var measurements: [BLEMeasurement]
    var searchMode: String
    var mapType: String
    var strongestMeasurementId: UUID?
    /// Timeline-Ereignisse gehören zur Session (nicht global).
    var events: [BLESearchEvent]
    /// Baseline-Fingerprint der Session (technisch, kein Scooter-Persist).
    var baselineFingerprint: BLEDeviceFingerprint?

    init(
        id: UUID = UUID(),
        deviceId: UUID,
        deviceName: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        measurements: [BLEMeasurement] = [],
        searchMode: BLESearchModeKind = .coarse,
        mapType: String = "relativeHeatmap",
        strongestMeasurementId: UUID? = nil,
        events: [BLESearchEvent] = [],
        baselineFingerprint: BLEDeviceFingerprint? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.measurements = measurements
        self.searchMode = searchMode.rawValue
        self.mapType = mapType
        self.strongestMeasurementId = strongestMeasurementId
        self.events = events
        self.baselineFingerprint = baselineFingerprint
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var strongestMeasurement: BLEMeasurement? {
        if let id = strongestMeasurementId {
            return measurements.first { $0.id == id }
        }
        return measurements.max(by: { $0.smoothedRssi < $1.smoothedRssi })
    }

    enum CodingKeys: String, CodingKey {
        case id, deviceId, deviceName, startedAt, endedAt, measurements
        case searchMode, mapType, strongestMeasurementId, events, baselineFingerprint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        deviceId = try c.decode(UUID.self, forKey: .deviceId)
        deviceName = try c.decode(String.self, forKey: .deviceName)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        measurements = try c.decodeIfPresent([BLEMeasurement].self, forKey: .measurements) ?? []
        searchMode = try c.decodeIfPresent(String.self, forKey: .searchMode) ?? BLESearchModeKind.coarse.rawValue
        mapType = try c.decodeIfPresent(String.self, forKey: .mapType) ?? "relativeHeatmap"
        strongestMeasurementId = try c.decodeIfPresent(UUID.self, forKey: .strongestMeasurementId)
        events = try c.decodeIfPresent([BLESearchEvent].self, forKey: .events) ?? []
        baselineFingerprint = try c.decodeIfPresent(BLEDeviceFingerprint.self, forKey: .baselineFingerprint)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(deviceName, forKey: .deviceName)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encode(measurements, forKey: .measurements)
        try c.encode(searchMode, forKey: .searchMode)
        try c.encode(mapType, forKey: .mapType)
        try c.encodeIfPresent(strongestMeasurementId, forKey: .strongestMeasurementId)
        try c.encode(events, forKey: .events)
        try c.encodeIfPresent(baselineFingerprint, forKey: .baselineFingerprint)
    }
}

/// Einfache Persistenz für abgeschlossene Suchverläufe.
@MainActor
final class BLESearchStore {
    static let shared = BLESearchStore()
    private let key = "bleSearchSessions.v1"
    private(set) var saved: [BLESearchSession] = []

    private init() {
        load()
    }

    func save(_ session: BLESearchSession) {
        var copy = session
        if copy.endedAt == nil { copy.endedAt = Date() }
        saved.removeAll { $0.id == copy.id }
        saved.insert(copy, at: 0)
        if saved.count > 40 { saved = Array(saved.prefix(40)) }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BLESearchSession].self, from: data) else {
            saved = []
            return
        }
        saved = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Heatmap

struct BLEHeatmapCell: Equatable, Sendable {
    var rssi: Double
    var weight: Double
    var samples: Int

    var confidence: Double {
        min(1.0, 0.22 + Double(samples) * 0.12 + weight * 0.15)
    }
}

struct BLEHeatmapSnapshot: Equatable, Sendable {
    var originEast: Double
    var originNorth: Double
    var cellSize: Double
    var cols: Int
    var rows: Int
    /// row-major, nil = ununtersucht
    var cells: [BLEHeatmapCell?]
    var trail: [(x: Double, y: Double)]
    var strongestCell: (col: Int, row: Int)?
    var boundsMeters: Double

    static let empty = BLEHeatmapSnapshot(
        originEast: 0, originNorth: 0,
        cellSize: BLESignalConfig.cellSizeMeters,
        cols: BLESignalConfig.heatmapCols,
        rows: BLESignalConfig.heatmapRows,
        cells: Array(repeating: nil, count: BLESignalConfig.heatmapCols * BLESignalConfig.heatmapRows),
        trail: [],
        strongestCell: nil,
        boundsMeters: 40
    )

    /// Manuell, weil gelabelte Tuples nicht auto-synthetisiert werden.
    static func == (lhs: BLEHeatmapSnapshot, rhs: BLEHeatmapSnapshot) -> Bool {
        guard lhs.originEast == rhs.originEast,
              lhs.originNorth == rhs.originNorth,
              lhs.cellSize == rhs.cellSize,
              lhs.cols == rhs.cols,
              lhs.rows == rhs.rows,
              lhs.boundsMeters == rhs.boundsMeters,
              lhs.cells == rhs.cells,
              lhs.trail.count == rhs.trail.count else { return false }
        for i in lhs.trail.indices {
            if lhs.trail[i].x != rhs.trail[i].x || lhs.trail[i].y != rhs.trail[i].y {
                return false
            }
        }
        switch (lhs.strongestCell, rhs.strongestCell) {
        case (nil, nil): return true
        case let (l?, r?): return l.col == r.col && l.row == r.row
        default: return false
        }
    }
}

enum BLEHeatmapProcessor {
    /// Baut Grid aus lokalen relativen Messpunkten (Meter ENU / Dead-Reckoning).
    static func build(from measurements: [BLEMeasurement]) -> BLEHeatmapSnapshot {
        let plotted = measurements.compactMap { m -> (x: Double, y: Double, rssi: Double, w: Double)? in
            guard let x = m.relativeX, let y = m.relativeY else { return nil }
            let w = m.quality.weight
            guard w > 0.05 else { return nil }
            return (x, y, m.smoothedRssi, w)
        }
        guard !plotted.isEmpty else { return .empty }

        let xs = plotted.map(\.x)
        let ys = plotted.map(\.y)
        let midX = (xs.min()! + xs.max()!) / 2
        let midY = (ys.min()! + ys.max()!) / 2
        let span = max(
            abs(xs.max()! - xs.min()!),
            abs(ys.max()! - ys.min()!),
            12
        )
        let bounds = min(90, max(24, span * 1.35))
        let cell = BLESignalConfig.cellSizeMeters
        let cols = BLESignalConfig.heatmapCols
        let rows = BLESignalConfig.heatmapRows
        let originEast = midX - bounds / 2
        let originNorth = midY - bounds / 2

        var cells: [BLEHeatmapCell?] = Array(repeating: nil, count: cols * rows)

        for p in plotted {
            let c = Int(((p.x - originEast) / cell).rounded(.down))
            let r = Int(((p.y - originNorth) / cell).rounded(.down))
            guard c >= 0, c < cols, r >= 0, r < rows else { continue }
            let idx = r * cols + c
            if var existing = cells[idx] {
                let tw = existing.weight + p.w
                existing.rssi = (existing.rssi * existing.weight + p.rssi * p.w) / max(tw, 0.001)
                existing.weight = tw
                existing.samples += 1
                cells[idx] = existing
            } else {
                cells[idx] = BLEHeatmapCell(rssi: p.rssi, weight: p.w, samples: 1)
            }
        }

        // Sanfte Nachbarschafts-Interpolation nur in Reichweite echter Zellen.
        cells = softFill(cells: cells, cols: cols, rows: rows, cellSize: cell)

        var strongest: (Int, Int)?
        var best = -999.0
        for r in 0..<rows {
            for c in 0..<cols {
                if let cell = cells[r * cols + c], cell.rssi > best, cell.samples > 0 {
                    best = cell.rssi
                    strongest = (c, r)
                }
            }
        }

        let trail = plotted.suffix(180).map { (x: $0.x, y: $0.y) }
        return BLEHeatmapSnapshot(
            originEast: originEast,
            originNorth: originNorth,
            cellSize: cell,
            cols: cols,
            rows: rows,
            cells: cells,
            trail: Array(trail),
            strongestCell: strongest,
            boundsMeters: bounds
        )
    }

    private static func softFill(
        cells: [BLEHeatmapCell?],
        cols: Int,
        rows: Int,
        cellSize: Double
    ) -> [BLEHeatmapCell?] {
        let maxR = BLESignalConfig.maxExtrapolationMeters / cellSize
        var out = cells
        for r in 0..<rows {
            for c in 0..<cols {
                if cells[r * cols + c] != nil { continue }
                var num = 0.0
                var den = 0.0
                var samples = 0
                let scan = Int(ceil(maxR))
                for dr in -scan...scan {
                    for dc in -scan...scan {
                        let rr = r + dr
                        let cc = c + dc
                        guard rr >= 0, rr < rows, cc >= 0, cc < cols else { continue }
                        guard let src = cells[rr * cols + cc], src.samples > 0 else { continue }
                        let dist = hypot(Double(dr), Double(dc))
                        guard dist > 0, dist <= maxR else { continue }
                        let w = src.weight / (dist * dist)
                        num += src.rssi * w
                        den += w
                        samples += 1
                    }
                }
                if den > 0.08, samples >= 1 {
                    out[r * cols + c] = BLEHeatmapCell(
                        rssi: num / den,
                        weight: den * 0.35,
                        samples: 0 // interpoliert — geringere Sicherheit
                    )
                }
            }
        }
        return out
    }

    /// Farbe für geglättetes RSSI (Mint → Gelb → Orange → Rot). nil = ununtersucht.
    static func color(forRssi rssi: Double?, confidence: Double) -> Color? {
        guard let rssi else { return nil }
        let t = normalizedStrength(rssi)
        let base: Color
        switch t {
        case 0.75...1.0:
            base = Theme.accent
        case 0.55..<0.75:
            base = Color(red: 0.55, green: 0.86, blue: 0.42)
        case 0.38..<0.55:
            base = Color(red: 0.92, green: 0.82, blue: 0.28)
        case 0.22..<0.38:
            base = Theme.hintOrange
        default:
            base = Color(red: 0.75, green: 0.28, blue: 0.28)
        }
        let alpha = 0.18 + 0.55 * min(1.0, max(0.15, confidence))
        return base.opacity(alpha)
    }

    /// 0 = sehr schwach, 1 = sehr stark.
    static func normalizedStrength(_ rssi: Double) -> Double {
        let minV = -95.0
        let maxV = -45.0
        return min(1, max(0, (rssi - minV) / (maxV - minV)))
    }
}
