import Foundation
import CoreLocation
import CoreMotion
import SwiftUI
import MapKit

// MARK: - View / surface mode

enum BLESearchSurfaceMode: String, Sendable, CaseIterable {
    /// Live-Signalstatus (RSSI, Trend, Kennzahlen).
    case live
    /// Bisherige 2D-Heatmap (Nutzer zentriert).
    case heatmap
    /// AR Signal-Finder (Kamera + bodenverankerte Signalflächen).
    case ar
    /// Outdoor Apple-Karte (optional, über Optionen).
    case map

    var label: String {
        switch self {
        case .live: return "Live"
        case .heatmap: return "Heatmap"
        case .ar: return "AR"
        case .map: return "Karte"
        }
    }

    var detailLabel: String {
        switch self {
        case .live: return "Live · Signal & Trend"
        case .heatmap: return "Heatmap · Nutzer zentriert"
        case .ar: return "AR Signal-Finder"
        case .map: return "Outdoor · Apple-Karte"
        }
    }

    /// Segmentierte Hauptauswahl: Live | Heatmap | AR
    static var primaryModes: [BLESearchSurfaceMode] { [.live, .heatmap, .ar] }
}

// MARK: - Path point

struct BLEPathPoint: Equatable, Sendable, Identifiable {
    var id: UUID
    var timestamp: Date
    /// Relative ENU meters (x = East, y = North).
    var x: Double
    var y: Double
    var headingDegrees: Double?
    var latitude: Double?
    var longitude: Double?
    var isStep: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        x: Double,
        y: Double,
        headingDegrees: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isStep: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.headingDegrees = headingDegrees
        self.latitude = latitude
        self.longitude = longitude
        self.isStep = isStep
    }
}

struct BLESearchViewport: Equatable, Sendable {
    var centerX: Double
    var centerY: Double
    var spanMeters: Double

    static let empty = BLESearchViewport(centerX: 0, centerY: 0, spanMeters: 16)

    var originEast: Double { centerX - spanMeters / 2 }
    var originNorth: Double { centerY - spanMeters / 2 }
}

struct BLESearchPathSnapshot: Equatable, Sendable {
    var points: [BLEPathPoint]
    var smoothedPolyline: [(x: Double, y: Double)]
    var pathLengthMeters: Double
    var viewport: BLESearchViewport
    var current: BLEPathPoint?

    static let empty = BLESearchPathSnapshot(
        points: [],
        smoothedPolyline: [],
        pathLengthMeters: 0,
        viewport: .empty,
        current: nil
    )

    static func == (lhs: BLESearchPathSnapshot, rhs: BLESearchPathSnapshot) -> Bool {
        guard lhs.pathLengthMeters == rhs.pathLengthMeters,
              lhs.viewport == rhs.viewport,
              lhs.points.count == rhs.points.count,
              lhs.smoothedPolyline.count == rhs.smoothedPolyline.count,
              lhs.current?.headingDegrees == rhs.current?.headingDegrees,
              lhs.current?.x == rhs.current?.x,
              lhs.current?.y == rhs.current?.y else { return false }
        for i in lhs.smoothedPolyline.indices {
            if lhs.smoothedPolyline[i].x != rhs.smoothedPolyline[i].x
                || lhs.smoothedPolyline[i].y != rhs.smoothedPolyline[i].y {
                return false
            }
        }
        return true
    }
}

// MARK: - Config

enum BLEPathConfig {
    /// Fallback-Schrittlänge, bis Pedometer-Distanz kalibriert.
    static let stepLengthMeters: Double = 0.72
    static let minCalibratedStepLength: Double = 0.48
    static let maxCalibratedStepLength: Double = 0.98
    static let minStepDistance: Double = 0.22
    static let minHeadingChangeDegrees: Double = 6
    /// Gyro-first: Drehungen aus Device-Motion übernehmen.
    static let gyroHeadingAlpha: Double = 0.72
    /// Kompass nur als weiche Absolut-Ankerung beim Laufen.
    static let compassAnchorAlpha: Double = 0.07
    /// Drehung auf der Stelle: Kompass stärker → Sichtkegel/Radar reagiert sofort.
    static let compassTurnAlpha: Double = 0.38
    static let compassMaxAccuracyDegrees: Double = 28
    /// Gyro-Mindestwinkel im Stillstand (rad) — niedrig genug für Handydrehung.
    static let gyroStandstillMinRadians: Double = 0.016
    static let gyroWalkingMinRadians: Double = 0.012
    static let minMoveForSample: Double = 0.28
    static let standstillAccelMax: Double = 0.11
    static let walkingAccelMin: Double = 0.16
    static let viewportPadding: Double = 1.45
    static let viewportMinSpan: Double = 10
    static let viewportMaxSpan: Double = 80
    static let viewportSoftFollow: Double = 0.22
    /// Live-Ansicht: fester Suchradius um den Nutzer (Karte bewegt sich, Nutzer bleibt mittig).
    static let liveCenterSpanMeters: Double = 22
    static let liveCenterSpanMaxMeters: Double = 36
    static let liveCenterFollow: Double = 0.55
    static let mapMinSpanMeters: Double = 16
    static let mapMaxSpanMeters: Double = 100
    static let mapPadding: Double = 1.55
    static let mapSoftFollow: Double = 0.28
    /// GPS darf nur bei dieser Horizontalgenauigkeit (Meter) die Karte/PDR führen.
    static let gpsFusionMaxAccuracy: Double = 8
    /// So viele aufeinanderfolgende gute Fixes, bevor die Apple-Karte erscheint.
    static let mapAccuracyStreakRequired = 3
    static let maxPathPoints = 800
}

/// Ein Messpunkt mit eingefrorenem RSSI (WLAN-Analyzer-Stil).
struct BLEBreadcrumb: Equatable, Sendable {
    var x: Double
    var y: Double
    var rssi: Double
}

// MARK: - Indoor motion tracker (PDR)

/// Relative Bewegung: Gyro-Drehungen + kalibrierte Pedometer-Distanz — keine Zentimeter-Präzision.
final class IndoorMotionTracker {
    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private var lastStepCount = 0
    private var lastPedometerDistance: Double = 0
    private var calibratedStepLength = BLEPathConfig.stepLengthMeters
    private var smoothedHeading: Double?
    private var x: Double = 0
    private var y: Double = 0
    private var lastEmit = Date.distantPast
    private var usePedometer = false
    private var lastAccelMag: Double = 0.05
    private var stepCooldownUntil = Date.distantPast
    private var lastYawRadians: Double?
    private var isWalking = false
    private var lastWalkAt = Date.distantPast
    /// Wenn ARKit/Kamera führt: Pedometer nicht zusätzlich Meter aufaddieren.
    private var visualPrimary = false
    private(set) var path: [BLEPathPoint] = []
    /// Summe der tatsächlich fortgeschriebenen Meter (Pedometer-Distanz / kalibrierte Schritte / Kamera).
    private(set) var traveledDistanceMeters: Double = 0

    var currentX: Double { x }
    var currentY: Double { y }
    var headingDegrees: Double? { smoothedHeading }
    var stepLengthMeters: Double { calibratedStepLength }
    /// Live-Heading für Sichtkegel (Heatmap/AR), auch ohne neuen Pfadpunkt.
    var onHeadingUpdated: ((Double) -> Void)?

    func reset() {
        stop()
        lastStepCount = 0
        lastPedometerDistance = 0
        calibratedStepLength = BLEPathConfig.stepLengthMeters
        smoothedHeading = nil
        x = 0
        y = 0
        lastEmit = .distantPast
        usePedometer = false
        lastAccelMag = 0.05
        stepCooldownUntil = .distantPast
        lastYawRadians = nil
        isWalking = false
        lastWalkAt = .distantPast
        visualPrimary = false
        traveledDistanceMeters = 0
        path = [BLEPathPoint(x: 0, y: 0, isStep: false)]
    }

    func setVisualPrimary(_ enabled: Bool) {
        visualPrimary = enabled
    }

    func start() {
        reset()
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.05
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                self.updateWalkState(data.userAcceleration)
                self.ingestGyroYaw(data.attitude.yaw)
                self.ingestUserAccelerationFallback(data.userAcceleration)
            }
        }
        if CMPedometer.isStepCountingAvailable() {
            usePedometer = true
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self, let data else { return }
                DispatchQueue.main.async {
                    self.ingestPedometer(
                        steps: data.numberOfSteps.intValue,
                        distanceMeters: data.distance?.doubleValue
                    )
                }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    /// Kompass: Initial-Heading, weiche Ankerung beim Laufen, stärkere Drehung im Stillstand (Sichtkegel).
    func ingestExternalHeading(_ degrees: Double?, fromCompass: Bool = false, accuracy: Double? = nil) {
        guard let degrees else { return }
        if smoothedHeading == nil {
            applyHeading(degrees, alpha: 1.0, minDeltaScale: 0)
            return
        }
        guard fromCompass else { return }
        let acc = accuracy ?? 999
        guard acc >= 0, acc <= BLEPathConfig.compassMaxAccuracyDegrees else { return }
        let recentlyWalking = isWalking || Date().timeIntervalSince(lastWalkAt) < 1.2
        if recentlyWalking {
            // Indoor oft magnetisch gestört: beim Laufen nur leicht nachziehen
            applyHeading(degrees, alpha: BLEPathConfig.compassAnchorAlpha, minDeltaScale: 0.15)
        } else {
            // Drehung auf der Stelle → Sichtkegel/Radar sofort mit Kompass
            applyHeading(degrees, alpha: BLEPathConfig.compassTurnAlpha, minDeltaScale: 0.06)
        }
    }

    func ingestGPSDelta(east: Double, north: Double, accuracy: Double) {
        guard accuracy > 0, accuracy <= BLEPathConfig.gpsFusionMaxAccuracy else { return }
        guard isWalking else { return }
        let dist = hypot(east - x, north - y)
        guard dist >= 1.2 else { return }
        x = x * 0.85 + east * 0.15
        y = y * 0.85 + north * 0.15
        appendIfMoved(isStep: false)
    }

    /// ARKit-/Kamera-Pose als primäre Indoor-Position (Meter auf der Bodenebene).
    /// `authoritative`: bei normalem Tracking Position direkt übernehmen.
    func ingestVisualPose(east: Double, north: Double, headingDegrees: Double?, authoritative: Bool) {
        let dist = hypot(east - x, north - y)
        if authoritative {
            visualPrimary = true
            if dist >= 0.03 {
                traveledDistanceMeters += dist
                x = east
                y = north
                isWalking = true
                lastWalkAt = Date()
                appendIfMoved(isStep: true)
            } else {
                x = east
                y = north
            }
        } else if dist >= 0.08 {
            // Limited tracking: weich mischen
            x = x * 0.55 + east * 0.45
            y = y * 0.55 + north * 0.45
            if visualPrimary {
                traveledDistanceMeters += dist
            } else {
                traveledDistanceMeters += dist * 0.45
            }
            appendIfMoved(isStep: false)
        }
        if let h = headingDegrees {
            applyHeading(h, alpha: authoritative ? 0.55 : 0.25, minDeltaScale: 0.08)
        }
    }

    // MARK: Gyro-first heading

    private func ingestGyroYaw(_ yawRadians: Double) {
        defer { lastYawRadians = yawRadians }
        guard let prev = lastYawRadians else {
            if smoothedHeading == nil { smoothedHeading = 0 }
            return
        }
        var dyaw = yawRadians - prev
        while dyaw > .pi { dyaw -= 2 * .pi }
        while dyaw < -.pi { dyaw += 2 * .pi }

        // Stillstand: leichter Driftfilter; Drehung am Handy trotzdem reagibel für den Sichtkegel
        let minRad = isWalking
            ? BLEPathConfig.gyroWalkingMinRadians
            : BLEPathConfig.gyroStandstillMinRadians
        guard abs(dyaw) >= minRad else { return }

        let ddeg = dyaw * 180 / .pi
        // CMAttitude.yaw: Zunahme ≈ Linksdrehung von oben → Heading verringern (Kompass-Konvention)
        let next = (smoothedHeading ?? 0) - ddeg
        applyHeading(next, alpha: BLEPathConfig.gyroHeadingAlpha, minDeltaScale: 0.04)
    }

    private func updateWalkState(_ accel: CMAcceleration) {
        let mag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
        lastAccelMag = mag * 0.4 + lastAccelMag * 0.6
        if lastAccelMag >= BLEPathConfig.walkingAccelMin {
            isWalking = true
            lastWalkAt = Date()
        } else if lastAccelMag <= BLEPathConfig.standstillAccelMax,
                  Date().timeIntervalSince(lastWalkAt) > 0.55 {
            isWalking = false
        }
    }

    /// Fallback-Schritte nur ohne Pedometer und nur bei klarer Bewegung.
    private func ingestUserAccelerationFallback(_ accel: CMAcceleration) {
        guard !usePedometer, smoothedHeading != nil, isWalking else { return }
        let mag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
        let now = Date()
        if mag > 0.24, lastAccelMag < 0.16, now > stepCooldownUntil {
            stepCooldownUntil = now.addingTimeInterval(0.36)
            advanceByMeters(calibratedStepLength)
        }
    }

    private func applyHeading(_ raw: Double, alpha: Double, minDeltaScale: Double) {
        var h = raw.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let previous = smoothedHeading
        if let prev = previous {
            var delta = h - prev
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            if abs(delta) < BLEPathConfig.minHeadingChangeDegrees * minDeltaScale {
                return
            }
            smoothedHeading = normalize(prev + delta * alpha)
        } else {
            smoothedHeading = h
        }
        if let next = smoothedHeading {
            let changed: Bool = {
                guard let previous else { return true }
                var d = next - previous
                while d > 180 { d -= 360 }
                while d < -180 { d += 360 }
                return abs(d) >= 0.8
            }()
            if changed {
                onHeadingUpdated?(next)
            }
        }
    }

    // MARK: Distance / steps

    private func ingestPedometer(steps: Int, distanceMeters: Double?) {
        let stepDelta = steps - lastStepCount
        defer { lastStepCount = steps }

        if let distance = distanceMeters, distance > lastPedometerDistance {
            let dDist = distance - lastPedometerDistance
            lastPedometerDistance = distance
            if stepDelta > 0 {
                let instant = dDist / Double(stepDelta)
                if instant >= BLEPathConfig.minCalibratedStepLength,
                   instant <= BLEPathConfig.maxCalibratedStepLength {
                    calibratedStepLength = calibratedStepLength * 0.65 + instant * 0.35
                }
            }
            // Kamera führt → Pedometer nur kalibrieren, nicht zusätzlich laufen
            guard !visualPrimary else { return }
            if dDist >= 0.08 {
                isWalking = true
                lastWalkAt = Date()
                advanceByMeters(dDist)
            }
            return
        }

        guard !visualPrimary, stepDelta > 0 else { return }
        isWalking = true
        lastWalkAt = Date()
        advanceByMeters(Double(min(stepDelta, 4)) * calibratedStepLength)
    }

    private func advanceByMeters(_ meters: Double) {
        guard meters > 0.04, smoothedHeading != nil else { return }
        // In Segmente splitten, damit Heading-Änderungen während des Schritts sichtbar werden
        let segment = max(0.28, min(0.45, calibratedStepLength * 0.45))
        let count = max(1, Int((meters / segment).rounded(.up)))
        let each = meters / Double(count)
        for _ in 0..<count {
            guard let heading = smoothedHeading else { return }
            let rad = heading * .pi / 180
            x += sin(rad) * each
            y += cos(rad) * each
            traveledDistanceMeters += each
            appendIfMoved(isStep: true)
        }
    }

    private func advanceBySteps(_ count: Int) {
        guard count > 0 else { return }
        advanceByMeters(Double(count) * calibratedStepLength)
    }

    /// Test-/Engine-Hook: manueller Schritt mit bekanntem Heading.
    func debugAdvance(steps: Int, headingDegrees: Double) {
        applyHeading(headingDegrees, alpha: 1.0, minDeltaScale: 0)
        isWalking = true
        lastWalkAt = Date()
        advanceBySteps(steps)
    }

    /// Test-Hook: Gyro-Drehung in Grad (positiv = Linksdrehung / Heading sinkt).
    func debugApplyGyroTurn(degrees: Double) {
        let next = (smoothedHeading ?? 0) - degrees
        applyHeading(next, alpha: 1.0, minDeltaScale: 0)
    }

    private func appendIfMoved(isStep: Bool) {
        let now = Date()
        if let last = path.last {
            let d = hypot(x - last.x, y - last.y)
            if d < BLEPathConfig.minStepDistance, now.timeIntervalSince(lastEmit) < 0.55 {
                return
            }
        }
        lastEmit = now
        let pt = BLEPathPoint(
            timestamp: now,
            x: x,
            y: y,
            headingDegrees: smoothedHeading,
            isStep: isStep
        )
        path.append(pt)
        if path.count > BLEPathConfig.maxPathPoints {
            path.removeFirst(path.count - BLEPathConfig.maxPathPoints)
        }
    }

    private func normalize(_ d: Double) -> Double {
        var v = d.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }
}

// MARK: - Path reconstructor

enum SearchPathReconstructor {
    static func snapshot(
        from raw: [BLEPathPoint],
        previousViewport: BLESearchViewport?,
        followSoftly: Bool = true
    ) -> BLESearchPathSnapshot {
        guard !raw.isEmpty else { return .empty }
        let filtered = densifyFilter(raw)
        let poly = smoothPolyline(filtered.map { (x: $0.x, y: $0.y) })
        let length = pathLength(poly)
        let viewport = SearchViewportController.make(
            points: poly,
            current: filtered.last.map { (x: $0.x, y: $0.y) },
            previous: previousViewport,
            softFollow: followSoftly
        )
        return BLESearchPathSnapshot(
            points: filtered,
            smoothedPolyline: poly,
            pathLengthMeters: length,
            viewport: viewport,
            current: filtered.last
        )
    }

    /// Mindestabstand + Winkel-Schwellwert gegen Zacken.
    private static func densifyFilter(_ raw: [BLEPathPoint]) -> [BLEPathPoint] {
        guard var last = raw.first else { return [] }
        var out = [last]
        var lastHeading: Double?
        for p in raw.dropFirst() {
            let dx = p.x - last.x
            let dy = p.y - last.y
            let dist = hypot(dx, dy)
            guard dist >= BLEPathConfig.minMoveForSample else { continue }
            let heading = atan2(dx, dy) * 180 / .pi
            if let lh = lastHeading {
                var d = heading - lh
                while d > 180 { d -= 360 }
                while d < -180 { d += 360 }
                // Sehr kleine Richtungsänderungen bei kurzer Distanz unterdrücken
                if abs(d) < BLEPathConfig.minHeadingChangeDegrees, dist < 1.1 {
                    // trotzdem Position updaten, aber Heading halten
                    let merged = BLEPathPoint(
                        timestamp: p.timestamp,
                        x: p.x,
                        y: p.y,
                        headingDegrees: lh,
                        latitude: p.latitude,
                        longitude: p.longitude,
                        isStep: p.isStep
                    )
                    out[out.count - 1] = merged
                    last = merged
                    continue
                }
            }
            lastHeading = heading
            out.append(p)
            last = p
        }
        return out
    }

    /// Einfache Mittelwert-Glättung (3-Punkt) für lesbare Kurven.
    private static func smoothPolyline(_ pts: [(x: Double, y: Double)]) -> [(x: Double, y: Double)] {
        guard pts.count >= 3 else { return pts }
        var out: [(x: Double, y: Double)] = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let a = pts[i - 1]
            let b = pts[i]
            let c = pts[i + 1]
            out.append((
                x: (a.x + b.x * 2 + c.x) / 4,
                y: (a.y + b.y * 2 + c.y) / 4
            ))
        }
        out.append(pts[pts.count - 1])
        return out
    }

    private static func pathLength(_ pts: [(x: Double, y: Double)]) -> Double {
        guard pts.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 1..<pts.count {
            sum += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
        }
        return sum
    }
}

// MARK: - Viewport

enum SearchViewportController {
    /// Live-Suche: Viewport immer um den Nutzer; Span bleibt ruhig (kein Pfad-Bounding-Box-Zoom).
    static func make(
        points: [(x: Double, y: Double)],
        current: (x: Double, y: Double)?,
        previous: BLESearchViewport?,
        softFollow: Bool
    ) -> BLESearchViewport {
        let focus = current ?? points.last
        guard let focus else { return previous ?? .empty }

        // Span nur leicht wachsen, wenn der Pfad den Standardradius sprengt
        var span = BLEPathConfig.liveCenterSpanMeters
        if points.count >= 2 {
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            let reach = max(
                abs((xs.max() ?? focus.x) - focus.x),
                abs((xs.min() ?? focus.x) - focus.x),
                abs((ys.max() ?? focus.y) - focus.y),
                abs((ys.min() ?? focus.y) - focus.y)
            )
            if reach > span * 0.42 {
                span = min(BLEPathConfig.liveCenterSpanMaxMeters, max(span, reach * 2.2))
            }
        }

        var cx = focus.x
        var cy = focus.y
        if softFollow, let prev = previous {
            let a = BLEPathConfig.liveCenterFollow
            cx = prev.centerX * (1 - a) + cx * a
            cy = prev.centerY * (1 - a) + cy * a
            span = prev.spanMeters * (1 - a * 0.45) + span * (a * 0.45)
        }
        return BLESearchViewport(centerX: cx, centerY: cy, spanMeters: span)
    }

    static func recenter(on point: (x: Double, y: Double), span: Double? = nil) -> BLESearchViewport {
        BLESearchViewport(
            centerX: point.x,
            centerY: point.y,
            spanMeters: span ?? BLEPathConfig.liveCenterSpanMeters
        )
    }
}

// MARK: - Heatmap placement along path

enum HeatmapPlacementEngine {
    /// Baut Heatmap aus Messungen entlang des Pfads.
    ///
    /// Farben bleiben an Orten eingefroren, bis du denselben Rasterplatz
    /// erneut misst — dann zählt der neue Wert (last-write). Kein Peak-Mittel,
    /// kein Paint-Radius auf Nachbarn, feste Welt-Zellgröße gegen Zoom-Drift.
    static func build(
        measurements: [BLEMeasurement],
        viewport: BLESearchViewport,
        pathPolyline: [(x: Double, y: Double)]
    ) -> BLEHeatmapSnapshot {
        let cell = BLESignalConfig.cellSizeMeters
        // Welt-Raster absolut: gleiche Meter-Zelle behält Index-Logik beim Zoomen
        let originEast = (viewport.originEast / cell).rounded(.down) * cell
        let originNorth = (viewport.originNorth / cell).rounded(.down) * cell
        let cols = min(
            64,
            max(12, Int(ceil(max(viewport.spanMeters, cell) / cell)) + 1)
        )
        let rows = cols
        let bounds = Double(cols) * cell

        // Chronologisch: letzter Messwert pro Weltzelle gewinnt
        var worldRssi: [Int64: (rssi: Double, weight: Double)] = [:]
        for m in measurements {
            guard let x = m.relativeX, let y = m.relativeY else { continue }
            let w = m.quality.weight
            guard w > 0.05 else { continue }
            let key = worldKey(x: x, y: y, cell: cell)
            worldRssi[key] = (m.smoothedRssi, w)
        }

        var cells: [BLEHeatmapCell?] = Array(repeating: nil, count: cols * rows)
        let originCol = Int((originEast / cell).rounded(.down))
        let originRow = Int((originNorth / cell).rounded(.down))
        for (key, value) in worldRssi {
            let (wc, wr) = decodeWorldKey(key)
            let c = wc - originCol
            let r = wr - originRow
            guard c >= 0, c < cols, r >= 0, r < rows else { continue }
            // samples = 1 → Confidence bleibt stabil (Farbe ändert sich nur mit RSSI)
            cells[r * cols + c] = BLEHeatmapCell(
                rssi: value.rssi,
                weight: value.weight,
                samples: 1
            )
        }

        // Soft-Fill nur leere Nachbarn; gemessene Zellen werden nie überschrieben.
        cells = softFillNearPath(cells: cells, cols: cols, rows: rows, cell: cell)

        var strongest: (Int, Int)?
        var best = -999.0
        for r in 0..<rows {
            for c in 0..<cols {
                if let cell = cells[r * cols + c], cell.samples > 0, cell.rssi > best {
                    best = cell.rssi
                    strongest = (c, r)
                }
            }
        }

        let trail = pathPolyline.suffix(220).map { (x: $0.x, y: $0.y) }
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

    /// Raster-Schlüssel in Weltkoordinaten (nicht Viewport-Index).
    static func worldKey(x: Double, y: Double, cell: Double = BLESignalConfig.cellSizeMeters) -> Int64 {
        let c = Int32((x / cell).rounded(.down))
        let r = Int32((y / cell).rounded(.down))
        return (Int64(c) << 32) | Int64(UInt32(bitPattern: r))
    }

    static func decodeWorldKey(_ key: Int64) -> (col: Int, row: Int) {
        let c = Int(Int32(truncatingIfNeeded: key >> 32))
        let r = Int(Int32(bitPattern: UInt32(truncatingIfNeeded: key)))
        return (c, r)
    }

    /// RSSI einer gemessenen Weltzelle (nil = noch nie / außerhalb).
    static func measuredRssi(
        in snapshot: BLEHeatmapSnapshot,
        x: Double,
        y: Double
    ) -> Double? {
        let cell = snapshot.cellSize
        guard cell > 0 else { return nil }
        let c = Int(((x - snapshot.originEast) / cell).rounded(.down))
        let r = Int(((y - snapshot.originNorth) / cell).rounded(.down))
        guard c >= 0, c < snapshot.cols, r >= 0, r < snapshot.rows else { return nil }
        let entry = snapshot.cells[r * snapshot.cols + c]
        guard let entry, entry.samples > 0 else { return nil }
        return entry.rssi
    }

    private static func softFillNearPath(
        cells: [BLEHeatmapCell?],
        cols: Int,
        rows: Int,
        cell: Double
    ) -> [BLEHeatmapCell?] {
        let maxR = min(2.2, BLESignalConfig.maxExtrapolationMeters / max(cell, 0.1))
        var out = cells
        let scan = Int(ceil(maxR))
        for r in 0..<rows {
            for c in 0..<cols {
                if cells[r * cols + c] != nil { continue }
                var num = 0.0
                var den = 0.0
                var samples = 0
                for dr in -scan...scan {
                    for dc in -scan...scan {
                        let rr = r + dr
                        let cc = c + dc
                        guard rr >= 0, rr < rows, cc >= 0, cc < cols else { continue }
                        guard let src = cells[rr * cols + cc], src.samples > 0 else { continue }
                        let dist = hypot(Double(dr), Double(dc))
                        guard dist > 0, dist <= maxR else { continue }
                        let w = 1.0 / (dist * dist)
                        num += src.rssi * w
                        den += w
                        samples += 1
                    }
                }
                // Interpolierte Zellen: schwächer und klar als „nicht gemessen“ (samples = 0)
                if den > 0, samples >= 2 {
                    out[r * cols + c] = BLEHeatmapCell(
                        rssi: num / den,
                        weight: den * 0.12,
                        samples: 0
                    )
                }
            }
        }
        return out
    }
}

// MARK: - Map helpers

struct BLEMapOverlayModel: Equatable {
    var coordinates: [CLLocationCoordinate2D]
    var heatSamples: [(coord: CLLocationCoordinate2D, rssi: Double)]
    var current: CLLocationCoordinate2D?
    var region: MKCoordinateRegion

    static func == (lhs: BLEMapOverlayModel, rhs: BLEMapOverlayModel) -> Bool {
        lhs.coordinates.count == rhs.coordinates.count
            && lhs.heatSamples.count == rhs.heatSamples.count
            && lhs.current?.latitude == rhs.current?.latitude
            && lhs.region.center.latitude == rhs.region.center.latitude
            && lhs.region.span.latitudeDelta == rhs.region.span.latitudeDelta
    }

    static let empty = BLEMapOverlayModel(
        coordinates: [],
        heatSamples: [],
        current: nil,
        region: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405),
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )
    )
}

enum OutdoorMapTracker {
    static func model(
        origin: CLLocation?,
        path: [BLEPathPoint],
        smoothedPolyline: [(x: Double, y: Double)],
        measurements: [BLEMeasurement],
        lastGPS: CLLocation?,
        previousRegion: MKCoordinateRegion?,
        softFollow: Bool
    ) -> BLEMapOverlayModel {
        guard let origin else {
            // Kein stabiler Ursprung → keine Karte mit springendem Roh-GPS.
            return .empty
        }

        func toCoord(x: Double, y: Double) -> CLLocationCoordinate2D {
            let mPerDegLat = 111_320.0
            let mPerDegLon = max(1e-6, 111_320.0 * cos(origin.coordinate.latitude * .pi / 180))
            return CLLocationCoordinate2D(
                latitude: origin.coordinate.latitude + y / mPerDegLat,
                longitude: origin.coordinate.longitude + x / mPerDegLon
            )
        }

        // Polyline aus geglättetem PDR-Pfad — nicht aus rohem Indoor-GPS.
        let polyENU = smoothedPolyline.isEmpty
            ? path.map { (x: $0.x, y: $0.y) }
            : smoothedPolyline
        let coords = polyENU.map { toCoord(x: $0.x, y: $0.y) }

        // Heat/Messpunkte immer entlang relativer Bewegung (WLAN-Analyzer-Stil).
        // Rohe GPS-Koordinaten indoor erzeugen den „Kritzel-Haufen“.
        let heats: [(CLLocationCoordinate2D, Double)] = measurements.compactMap { m in
            guard let x = m.relativeX, let y = m.relativeY else { return nil }
            return (toCoord(x: x, y: y), m.smoothedRssi)
        }

        let current = path.last.map { toCoord(x: $0.x, y: $0.y) }
            ?? polyENU.last.map { toCoord(x: $0.x, y: $0.y) }
            ?? lastGPS?.coordinate

        let region = fittedRegion(
            enuPoints: polyENU,
            currentENU: path.last.map { (x: $0.x, y: $0.y) },
            origin: origin,
            previous: previousRegion,
            softFollow: softFollow
        )

        return BLEMapOverlayModel(
            coordinates: coords,
            heatSamples: heats.map { (coord: $0.0, rssi: $0.1) },
            current: current,
            region: region
        )
    }

    /// Zoom eng um den gelaufenen Weg; wächst mit der Strecke.
    static func fittedRegion(
        enuPoints: [(x: Double, y: Double)],
        currentENU: (x: Double, y: Double)?,
        origin: CLLocation,
        previous: MKCoordinateRegion?,
        softFollow: Bool
    ) -> MKCoordinateRegion {
        var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0
        if let first = enuPoints.first {
            minX = first.x; maxX = first.x; minY = first.y; maxY = first.y
            for p in enuPoints.dropFirst() {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        if let c = currentENU {
            minX = min(minX, c.x); maxX = max(maxX, c.x)
            minY = min(minY, c.y); maxY = max(maxY, c.y)
        }
        let width = max(maxX - minX, 2)
        let height = max(maxY - minY, 2)
        let span = min(
            BLEPathConfig.mapMaxSpanMeters,
            max(BLEPathConfig.mapMinSpanMeters, max(width, height) * BLEPathConfig.mapPadding)
        )
        var cx = (minX + maxX) / 2
        var cy = (minY + maxY) / 2
        if let c = currentENU {
            cx = cx * 0.5 + c.x * 0.5
            cy = cy * 0.5 + c.y * 0.5
        }

        let mPerDegLat = 111_320.0
        let mPerDegLon = max(1e-6, 111_320.0 * cos(origin.coordinate.latitude * .pi / 180))
        var center = CLLocationCoordinate2D(
            latitude: origin.coordinate.latitude + cy / mPerDegLat,
            longitude: origin.coordinate.longitude + cx / mPerDegLon
        )
        var meters = span

        if softFollow, let prev = previous {
            let prevMeters = max(
                prev.span.latitudeDelta * mPerDegLat,
                prev.span.longitudeDelta * mPerDegLon
            )
            let a = BLEPathConfig.mapSoftFollow
            center = CLLocationCoordinate2D(
                latitude: prev.center.latitude * (1 - a) + center.latitude * a,
                longitude: prev.center.longitude * (1 - a) + center.longitude * a
            )
            meters = prevMeters * (1 - a) + span * a
        }

        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
    }
}
