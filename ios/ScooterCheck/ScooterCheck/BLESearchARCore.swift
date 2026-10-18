import Foundation
import SwiftUI
import UIKit

// MARK: - Fixed RSSI color scale (no global re-normalization)

enum ARSignalColorScale {
    /// Mint/grün: stark
    static let strongMax: Double = -55
    /// Gelb: mittel
    static let mediumMax: Double = -68
    /// Orange: schwach
    static let weakMax: Double = -80
    // darunter: rot / sehr schwach

    static func uiColor(forRssi rssi: Double) -> UIColor {
        let stops: [(Double, UIColor)] = [
            (-45, UIColor(red: 0.42, green: 0.86, blue: 0.76, alpha: 1)), // mint
            (-55, UIColor(red: 0.38, green: 0.82, blue: 0.48, alpha: 1)),
            (-68, UIColor(red: 0.92, green: 0.82, blue: 0.28, alpha: 1)),
            (-80, UIColor(red: 0.95, green: 0.55, blue: 0.22, alpha: 1)),
            (-95, UIColor(red: 0.78, green: 0.28, blue: 0.28, alpha: 1))
        ]
        let r = min(-45, max(-100, rssi))
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            if r <= a.0 && r >= b.0 {
                let t = CGFloat((a.0 - r) / max(0.001, a.0 - b.0))
                return lerp(a.1, b.1, t)
            }
        }
        return stops.last!.1
    }

    static func swiftUIColor(forRssi rssi: Double) -> Color {
        Color(uiColor(forRssi: rssi))
    }

    private static func lerp(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
    }
}

// MARK: - AR options (persisted)

struct ARSignalFinderSettings: Equatable, Sendable {
    var showHeatmap = true
    var showPath = true
    var showBestZone = true
    var heatmapOpacity: Double = 0.55
    var showMinimap = true
    var showRawRssi = false
    var hapticsEnabled = false
    var audioEnabled = false

    private static let defaultsKey = "arSignalFinder.settings.v1"

    static func load() -> ARSignalFinderSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(Codec.self, from: data) else {
            return ARSignalFinderSettings()
        }
        return decoded.asSettings
    }

    func save() {
        let codec = Codec(from: self)
        if let data = try? JSONEncoder().encode(codec) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private struct Codec: Codable {
        var showHeatmap: Bool
        var showPath: Bool
        var showBestZone: Bool
        var heatmapOpacity: Double
        var showMinimap: Bool
        var showRawRssi: Bool
        var hapticsEnabled: Bool
        var audioEnabled: Bool

        init(from s: ARSignalFinderSettings) {
            showHeatmap = s.showHeatmap
            showPath = s.showPath
            showBestZone = s.showBestZone
            heatmapOpacity = s.heatmapOpacity
            showMinimap = s.showMinimap
            showRawRssi = s.showRawRssi
            hapticsEnabled = s.hapticsEnabled
            audioEnabled = s.audioEnabled
        }

        var asSettings: ARSignalFinderSettings {
            var s = ARSignalFinderSettings()
            s.showHeatmap = showHeatmap
            s.showPath = showPath
            s.showBestZone = showBestZone
            s.heatmapOpacity = heatmapOpacity
            s.showMinimap = showMinimap
            s.showRawRssi = showRawRssi
            s.hapticsEnabled = hapticsEnabled
            s.audioEnabled = audioEnabled
            return s
        }
    }
}

enum ARSignalFinderOnboarding {
    private static let key = "arSignalFinder.onboarding.done.v1"
    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Spatial sample & best zone

struct ARSpatialSample: Equatable, Sendable, Identifiable {
    let id: UUID
    var timestamp: Date
    /// ENU meters (x = East, y = North) — iPhone pose at measurement time.
    var x: Double
    var y: Double
    var rawRssi: Double
    var smoothedRssi: Double
    var trackingHealthy: Bool
    var sessionEpoch: Int

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        x: Double,
        y: Double,
        rawRssi: Double,
        smoothedRssi: Double,
        trackingHealthy: Bool,
        sessionEpoch: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.rawRssi = rawRssi
        self.smoothedRssi = smoothedRssi
        self.trackingHealthy = trackingHealthy
        self.sessionEpoch = sessionEpoch
    }
}

struct ARBestZone: Equatable, Sendable {
    var x: Double
    var y: Double
    var rssi: Double
    var sampleCount: Int
    var confirmedAt: Date
}

/// Robuste „beste Zone“ mit Hysterese — kein Springen auf Einzelspitzen.
struct ARBestZoneEstimator {
    private var pending: (x: Double, y: Double, rssi: Double, since: Date)?
    private(set) var confirmed: ARBestZone?
    /// Mindestverbesserung (dBm) und Nähe (m) für Wechsel.
    var hysteresisDb: Double = 4.0
    var confirmSeconds: TimeInterval = 1.6
    var mergeRadiusMeters: Double = 2.4

    mutating func reset() {
        pending = nil
        confirmed = nil
    }

    mutating func ingest(samples: [ARSpatialSample], now: Date = Date()) {
        let healthy = samples.filter { $0.trackingHealthy }
        guard healthy.count >= 3 else { return }

        // Räumliche Aggregation: 1.8 m Zellen, Median der geglätteten RSSI
        var buckets: [Int64: [Double]] = [:]
        var centers: [Int64: (sx: Double, sy: Double, n: Int)] = [:]
        let cell = 1.8
        for s in healthy {
            let cx = Int64(floor(s.x / cell))
            let cy = Int64(floor(s.y / cell))
            let key = (cx & 0xffff_ffff) << 32 | (cy & 0xffff_ffff)
            buckets[key, default: []].append(s.smoothedRssi)
            var c = centers[key] ?? (0, 0, 0)
            c.sx += s.x
            c.sy += s.y
            c.n += 1
            centers[key] = c
        }

        var bestKey: Int64?
        var bestMedian = -200.0
        var bestCount = 0
        for (key, values) in buckets where values.count >= 2 {
            let sorted = values.sorted()
            let med = sorted[sorted.count / 2]
            if med > bestMedian {
                bestMedian = med
                bestKey = key
                bestCount = values.count
            }
        }
        guard let key = bestKey, let c = centers[key], c.n > 0 else { return }
        let bx = c.sx / Double(c.n)
        let by = c.sy / Double(c.n)

        if let cur = confirmed {
            let dist = hypot(bx - cur.x, by - cur.y)
            if dist <= mergeRadiusMeters {
                // Gleiche Zone: Position leicht nachziehen, RSSI updaten wenn besser
                confirmed = ARBestZone(
                    x: cur.x * 0.85 + bx * 0.15,
                    y: cur.y * 0.85 + by * 0.15,
                    rssi: max(cur.rssi, bestMedian),
                    sampleCount: max(cur.sampleCount, bestCount),
                    confirmedAt: cur.confirmedAt
                )
                pending = nil
                return
            }
            // Neue Zone nur bei klar besserem Signal
            guard bestMedian >= cur.rssi + hysteresisDb else {
                pending = nil
                return
            }
        }

        if let p = pending, hypot(p.x - bx, p.y - by) <= mergeRadiusMeters {
            if now.timeIntervalSince(p.since) >= confirmSeconds {
                confirmed = ARBestZone(
                    x: bx, y: by, rssi: bestMedian,
                    sampleCount: bestCount, confirmedAt: now
                )
                pending = nil
            } else {
                pending = (bx, by, max(p.rssi, bestMedian), p.since)
            }
        } else {
            pending = (bx, by, bestMedian, now)
        }
    }
}

// MARK: - Guidance hints (hysteresis)

enum ARGuidanceHint: Equatable, Sendable {
    case moveToMap
    case stronger
    case weaker
    case stable
    case bestZoneDirection(String)
    case trackingLimited
    case noSignal
    case unclear

    var text: String {
        switch self {
        case .moveToMap: return "Bewege dich weiter, um neue Bereiche zu prüfen"
        case .stronger: return "Signal wird stärker"
        case .weaker: return "Signal wird schwächer"
        case .stable: return "Signal bleibt stabil"
        case .bestZoneDirection(let d): return "Bisher stärkster Messbereich \(d)"
        case .trackingLimited: return "AR-Tracking eingeschränkt"
        case .noSignal: return "Kein aktuelles Signal"
        case .unclear: return "Noch keine klare Tendenz erkennbar"
        }
    }
}

struct ARGuidanceController {
    private var lastHint: ARGuidanceHint = .unclear
    private var lastChangeAt: Date = .distantPast
    private let minHold: TimeInterval = 1.8

    mutating func reset() {
        lastHint = .unclear
        lastChangeAt = .distantPast
    }

    mutating func update(
        trend: BLESignalTrend,
        signalLost: Bool,
        trackingHealthy: Bool,
        sampleCount: Int,
        bestZone: ARBestZone?,
        currentX: Double?,
        currentY: Double?,
        headingDegrees: Double?,
        now: Date = Date()
    ) -> ARGuidanceHint {
        let candidate: ARGuidanceHint
        if !trackingHealthy {
            candidate = .trackingLimited
        } else if signalLost {
            candidate = .noSignal
        } else if sampleCount < 4 {
            candidate = .moveToMap
        } else if let zone = bestZone, let cx = currentX, let cy = currentY, let heading = headingDegrees {
            let dx = zone.x - cx
            let dy = zone.y - cy
            let dist = hypot(dx, dy)
            if dist >= 2.0 {
                candidate = .bestZoneDirection(Self.relativeDirection(dx: dx, dy: dy, heading: heading))
            } else {
                candidate = trendHint(trend)
            }
        } else {
            candidate = trendHint(trend)
        }

        if candidate == lastHint {
            return lastHint
        }
        if now.timeIntervalSince(lastChangeAt) < minHold,
           lastHint != .trackingLimited,
           candidate != .trackingLimited {
            return lastHint
        }
        lastHint = candidate
        lastChangeAt = now
        return lastHint
    }

    private func trendHint(_ trend: BLESignalTrend) -> ARGuidanceHint {
        switch trend {
        case .stronger: return .stronger
        case .weaker: return .weaker
        case .stable: return .stable
        }
    }

    static func relativeDirection(dx: Double, dy: Double, heading: Double) -> String {
        var bearing = atan2(dx, dy) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        var rel = bearing - heading
        while rel < -180 { rel += 360 }
        while rel > 180 { rel -= 360 }
        switch rel {
        case -22..<22: return "geradeaus"
        case 22..<67: return "rechts vorne"
        case 67..<112: return "rechts"
        case 112..<157: return "rechts hinten"
        case -67 ..< -22: return "links vorne"
        case -112 ..< -67: return "links"
        case -157 ..< -112: return "links hinten"
        default: return "hinten"
        }
    }
}

// MARK: - Floor texture builder (soft continuous, frozen cell colors)

enum ARFloorHeatmapRenderer {
    /// Baut eine transparente Textur: nur gemessene Bereiche, feste RSSI-Farben, weiche Kernel.
    static func makeTexture(
        samples: [ARSpatialSample],
        centerX: Double,
        centerY: Double,
        spanMeters: Double,
        opacity: Double,
        size: Int = 128
    ) -> UIImage? {
        guard !samples.isEmpty, spanMeters > 0.5 else { return nil }
        let side = max(64, min(192, size))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.clear(CGRect(x: 0, y: 0, width: side, height: side))
            let half = spanMeters / 2
            let sigma = 1.8
            let sigma2 = 2 * sigma * sigma
            // Zellen-Aggregation: letzte Messung pro ~1.2 m Zelle behält Farbe (kein globales Remap)
            var cellRssi: [Int64: Double] = [:]
            let cell = 1.2
            for s in samples {
                let cx = Int64(floor(s.x / cell))
                let cy = Int64(floor(s.y / cell))
                let key = (cx & 0xffff_ffff) << 32 | (cy & 0xffff_ffff)
                cellRssi[key] = s.smoothedRssi
            }
            var points: [(x: Double, y: Double, rssi: Double)] = []
            for (key, rssi) in cellRssi {
                let cx = Double(Int32(truncatingIfNeeded: key >> 32))
                let cy = Double(Int32(truncatingIfNeeded: key & 0xffff_ffff))
                points.append(((cx + 0.5) * cell, (cy + 0.5) * cell, rssi))
            }
            guard !points.isEmpty else { return }

            for iy in 0..<side {
                for ix in 0..<side {
                    let wx = centerX - half + (Double(ix) + 0.5) / Double(side) * spanMeters
                    // Image Y down; world north up → flip
                    let wy = centerY + half - (Double(iy) + 0.5) / Double(side) * spanMeters
                    var num = 0.0
                    var den = 0.0
                    for p in points {
                        let dx = wx - p.x
                        let dy = wy - p.y
                        let d2 = dx * dx + dy * dy
                        if d2 > 36 { continue }
                        let w = exp(-d2 / sigma2)
                        num += p.rssi * w
                        den += w
                    }
                    guard den > 0.22 else { continue }
                    let rssi = num / den
                    let coverage = min(1.0, den / 1.2)
                    let base = ARSignalColorScale.uiColor(forRssi: rssi)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    base.getRed(&r, green: &g, blue: &b, alpha: &a)
                    let alpha = CGFloat(opacity) * (0.18 + 0.72 * CGFloat(coverage))
                    cg.setFillColor(UIColor(red: r, green: g, blue: b, alpha: alpha).cgColor)
                    cg.fill(CGRect(x: ix, y: iy, width: 1, height: 1))
                }
            }
        }
    }
}
