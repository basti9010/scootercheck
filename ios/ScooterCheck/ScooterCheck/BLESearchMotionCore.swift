import Foundation
import CoreLocation
import CoreMotion
import SwiftUI
import MapKit

// MARK: - View / surface mode

enum BLESearchSurfaceMode: String, Sendable, CaseIterable {
    case relative
    case map

    var label: String {
        switch self {
        case .relative: return "Relativ"
        case .map: return "Karte"
        }
    }

    var detailLabel: String {
        switch self {
        case .relative: return "Indoor · relative Suchfläche"
        case .map: return "Outdoor · Apple-Karte"
        }
    }
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
              lhs.smoothedPolyline.count == rhs.smoothedPolyline.count else { return false }
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
    static let stepLengthMeters: Double = 0.70
    static let minStepDistance: Double = 0.28
    static let minHeadingChangeDegrees: Double = 8
    static let headingEmaAlpha: Double = 0.28
    /// Compass (CLHeading) darf stärker ziehen als Device-Yaw.
    static let compassHeadingAlpha: Double = 0.45
    static let minMoveForSample: Double = 0.32
    static let standstillSpeedMax: Double = 0.18
    static let viewportPadding: Double = 1.45
    static let viewportMinSpan: Double = 10
    static let viewportMaxSpan: Double = 80
    static let viewportSoftFollow: Double = 0.22
    /// Karten-Zoom eng am Laufweg — startet nah, wächst mit der Strecke.
    static let mapMinSpanMeters: Double = 18
    static let mapMaxSpanMeters: Double = 100
    static let mapPadding: Double = 1.55
    static let mapSoftFollow: Double = 0.28
    /// GPS nur bei wirklich guter Outdoor-Genauigkeit in den Pfad mischen.
    static let gpsFusionMaxAccuracy: Double = 8
    static let maxPathPoints = 800
    static let heatmapPaintRadius: Double = 1.8
}

// MARK: - Indoor motion tracker (PDR-light)

/// Relative Bewegung aus Schritten + geglättetem Heading — keine Zentimeter-Präzision.
final class IndoorMotionTracker {
    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private var lastStepCount = 0
    private var smoothedHeading: Double?
    private var x: Double = 0
    private var y: Double = 0
    private var lastEmit = Date.distantPast
    private var usePedometer = false
    private var lastAccelMag: Double = 1.0
    private var stepCooldownUntil = Date.distantPast
    private var lastUserAccelPeak = Date.distantPast
    /// Compass hat Vorrang vor Device-Yaw (vermeidet Misch-Sprünge).
    private var lastCompassAt = Date.distantPast
    private(set) var path: [BLEPathPoint] = []

    var currentX: Double { x }
    var currentY: Double { y }
    var headingDegrees: Double? { smoothedHeading }

    func reset() {
        stop()
        lastStepCount = 0
        smoothedHeading = nil
        x = 0
        y = 0
        lastEmit = .distantPast
        usePedometer = false
        lastAccelMag = 1.0
        stepCooldownUntil = .distantPast
        lastUserAccelPeak = .distantPast
        lastCompassAt = .distantPast
        path = [BLEPathPoint(x: 0, y: 0, isStep: false)]
    }

    func start() {
        reset()
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.06
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                self.ingestAttitude(data.attitude)
                self.ingestUserAcceleration(data.userAcceleration)
            }
        }
        if CMPedometer.isStepCountingAvailable() {
            usePedometer = true
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self, let data else { return }
                DispatchQueue.main.async {
                    self.ingestSteps(data.numberOfSteps.intValue)
                }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    /// CLHeading / Compass — bevorzugte Laufrichtung (wie WLAN-Analyzer-Feeling).
    func ingestExternalHeading(_ degrees: Double?, fromCompass: Bool = false) {
        guard let degrees else { return }
        if fromCompass {
            lastCompassAt = Date()
            applyHeading(degrees, alpha: BLEPathConfig.compassHeadingAlpha, minDeltaScale: 0.2)
        } else {
            applyHeading(degrees)
        }
    }

    func ingestGPSDelta(east: Double, north: Double, accuracy: Double) {
        // Indoor-GPS (oft 10–25 m) zerstört den Laufweg — nur echte Outdoor-Genauigkeit.
        guard accuracy > 0, accuracy <= BLEPathConfig.gpsFusionMaxAccuracy else { return }
        let dist = hypot(east - x, north - y)
        guard dist >= 1.2 else { return }
        // Sehr weiche Annäherung
        x = x * 0.82 + east * 0.18
        y = y * 0.82 + north * 0.18
        appendIfMoved(isStep: false)
    }

    private func ingestAttitude(_ attitude: CMAttitude) {
        // Compass aktiv → Yaw nicht mischen (sonst Richtungs-Zacken)
        if Date().timeIntervalSince(lastCompassAt) < 1.8 { return }
        var deg = attitude.yaw * 180 / .pi
        if deg < 0 { deg += 360 }
        applyHeading(deg, alpha: BLEPathConfig.headingEmaAlpha * 0.75, minDeltaScale: 0.5)
    }

    /// Fallback-Schritterkennung, wenn CMPedometer fehlt (Simulator / eingeschränkt).
    private func ingestUserAcceleration(_ accel: CMAcceleration) {
        guard !usePedometer, smoothedHeading != nil else { return }
        let mag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
        let now = Date()
        // Einfacher Peak-Detektor: Anstieg über Schwellwert, dann Abklingen
        if mag > 0.22, lastAccelMag < 0.18, now > stepCooldownUntil {
            stepCooldownUntil = now.addingTimeInterval(0.38)
            lastUserAccelPeak = now
            advanceBySteps(1)
        }
        lastAccelMag = mag * 0.35 + lastAccelMag * 0.65
        // Stehen bleiben: kein künstliches Weiterlaufen
        _ = lastUserAccelPeak
    }

    private func applyHeading(_ raw: Double, alpha: Double = BLEPathConfig.headingEmaAlpha, minDeltaScale: Double = 0.35) {
        var h = raw.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        if let prev = smoothedHeading {
            var delta = h - prev
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            // Kleine Rauschänderungen ignorieren
            if abs(delta) < BLEPathConfig.minHeadingChangeDegrees * minDeltaScale {
                return
            }
            let next = prev + delta * alpha
            smoothedHeading = normalize(next)
        } else {
            smoothedHeading = h
        }
    }

    private func ingestSteps(_ total: Int) {
        let delta = total - lastStepCount
        lastStepCount = total
        guard delta > 0 else { return }
        advanceBySteps(min(delta, 4))
    }

    private func advanceBySteps(_ count: Int) {
        guard count > 0, smoothedHeading != nil else { return }
        // Pro Schritt aktuelles Heading lesen → Kurven werden sichtbar (nicht ein Batch-Heading)
        for _ in 0..<count {
            guard let heading = smoothedHeading else { return }
            let rad = heading * .pi / 180
            // Heading 0 = Nord → y+, 90 = Ost → x+
            x += sin(rad) * BLEPathConfig.stepLengthMeters
            y += cos(rad) * BLEPathConfig.stepLengthMeters
            appendIfMoved(isStep: true)
        }
    }

    /// Test-/Engine-Hook: manueller Schritt mit bekanntem Heading.
    func debugAdvance(steps: Int, headingDegrees: Double) {
        applyHeading(headingDegrees, alpha: 1.0, minDeltaScale: 0)
        advanceBySteps(steps)
    }

    private func appendIfMoved(isStep: Bool) {
        let now = Date()
        if let last = path.last {
            let d = hypot(x - last.x, y - last.y)
            if d < BLEPathConfig.minStepDistance, now.timeIntervalSince(lastEmit) < 0.8 {
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
    static func make(
        points: [(x: Double, y: Double)],
        current: (x: Double, y: Double)?,
        previous: BLESearchViewport?,
        softFollow: Bool
    ) -> BLESearchViewport {
        guard !points.isEmpty else { return previous ?? .empty }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        var minX = xs.min()!
        var maxX = xs.max()!
        var minY = ys.min()!
        var maxY = ys.max()!
        if let c = current {
            minX = min(minX, c.x)
            maxX = max(maxX, c.x)
            minY = min(minY, c.y)
            maxY = max(maxY, c.y)
        }
        let width = max(maxX - minX, 4)
        let height = max(maxY - minY, 4)
        let span = min(
            BLEPathConfig.viewportMaxSpan,
            max(BLEPathConfig.viewportMinSpan, max(width, height) * BLEPathConfig.viewportPadding)
        )
        var cx = (minX + maxX) / 2
        var cy = (minY + maxY) / 2
        // Aktuellen Punkt leicht bevorzugen, ohne hektisch zu springen
        if let c = current {
            cx = cx * 0.55 + c.x * 0.45
            cy = cy * 0.55 + c.y * 0.45
        }
        if softFollow, let prev = previous {
            cx = prev.centerX * (1 - BLEPathConfig.viewportSoftFollow) + cx * BLEPathConfig.viewportSoftFollow
            cy = prev.centerY * (1 - BLEPathConfig.viewportSoftFollow) + cy * BLEPathConfig.viewportSoftFollow
            let softSpan = prev.spanMeters * (1 - BLEPathConfig.viewportSoftFollow) + span * BLEPathConfig.viewportSoftFollow
            return BLESearchViewport(centerX: cx, centerY: cy, spanMeters: softSpan)
        }
        return BLESearchViewport(centerX: cx, centerY: cy, spanMeters: span)
    }

    static func recenter(on point: (x: Double, y: Double), span: Double? = nil) -> BLESearchViewport {
        BLESearchViewport(
            centerX: point.x,
            centerY: point.y,
            spanMeters: span ?? BLEPathConfig.viewportMinSpan * 1.4
        )
    }
}

// MARK: - Heatmap placement along path

enum HeatmapPlacementEngine {
    /// Baut Heatmap aus Messungen entlang des Pfads.
    ///
    /// Warum ältere Farben früher „wanderten“:
    /// Beim Mittelwert haben neue schwächere Messungen alte starke Zellen verwässert,
    /// und Soft-Fill hat Nachbarschafts-Farben bei jedem Rebuild neu gemischt.
    /// Jetzt: Peak-RSSI in gemessenen Zellen + Origin am Raster eingerastet.
    static func build(
        measurements: [BLEMeasurement],
        viewport: BLESearchViewport,
        pathPolyline: [(x: Double, y: Double)]
    ) -> BLEHeatmapSnapshot {
        let cols = BLESignalConfig.heatmapCols
        let rows = BLESignalConfig.heatmapRows
        let bounds = max(viewport.spanMeters, 1)
        let cell = bounds / Double(cols)
        // Origin an fester Welt-Rasterkante einrasten → weniger Index-Verschiebung beim Zoomen
        let snap = BLESignalConfig.cellSizeMeters
        let originEast = (viewport.originEast / snap).rounded(.down) * snap
        let originNorth = (viewport.originNorth / snap).rounded(.down) * snap

        var cells: [BLEHeatmapCell?] = Array(repeating: nil, count: cols * rows)
        let plotted = measurements.compactMap { m -> (Double, Double, Double, Double)? in
            guard let x = m.relativeX, let y = m.relativeY else { return nil }
            let w = m.quality.weight
            guard w > 0.05 else { return nil }
            return (x, y, m.smoothedRssi, w)
        }

        let paintRadius = min(BLEPathConfig.heatmapPaintRadius, cell * 1.6)
        for p in plotted {
            paint(
                x: p.0, y: p.1, rssi: p.2, weight: p.3,
                into: &cells, cols: cols, rows: rows,
                originE: originEast, originN: originNorth,
                cell: cell, paintRadius: paintRadius
            )
        }

        // Nur lokal weich füllen — keine weite Extrapolation; überschreibt nie samples > 0.
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
                if den > 0, samples >= 2 {
                    out[r * cols + c] = BLEHeatmapCell(
                        rssi: num / den,
                        weight: den * 0.2,
                        samples: 0
                    )
                }
            }
        }
        return out
    }

    private static func paint(
        x: Double,
        y: Double,
        rssi: Double,
        weight: Double,
        into cells: inout [BLEHeatmapCell?],
        cols: Int,
        rows: Int,
        originE: Double,
        originN: Double,
        cell: Double,
        paintRadius: Double
    ) {
        let c0 = Int(((x - originE) / cell).rounded(.down))
        let r0 = Int(((y - originN) / cell).rounded(.down))
        let radiusCells = max(1, Int(ceil(paintRadius / cell)))
        for dr in -radiusCells...radiusCells {
            for dc in -radiusCells...radiusCells {
                let c = c0 + dc
                let r = r0 + dr
                guard c >= 0, c < cols, r >= 0, r < rows else { continue }
                let dist = hypot(Double(dc), Double(dr)) * cell
                guard dist <= paintRadius else { continue }
                let falloff = max(0.15, 1.0 - dist / paintRadius)
                let w = weight * falloff
                let idx = r * cols + c
                let isCore = dist < cell * 0.55
                if var existing = cells[idx] {
                    // Peak-RSSI: ältere starke Messungen nicht durch spätere schwächere Mittelwerte verwässern
                    existing.rssi = max(existing.rssi, rssi)
                    existing.weight = max(existing.weight, w)
                    if isCore { existing.samples += 1 }
                    cells[idx] = existing
                } else {
                    cells[idx] = BLEHeatmapCell(
                        rssi: rssi,
                        weight: w,
                        samples: isCore ? 1 : 0
                    )
                }
            }
        }
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
            if let gps = lastGPS {
                return BLEMapOverlayModel(
                    coordinates: [],
                    heatSamples: [],
                    current: gps.coordinate,
                    region: MKCoordinateRegion(
                        center: gps.coordinate,
                        latitudinalMeters: BLEPathConfig.mapMinSpanMeters,
                        longitudinalMeters: BLEPathConfig.mapMinSpanMeters
                    )
                )
            }
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
