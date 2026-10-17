import XCTest
import CoreLocation
@testable import ScooterCheck

final class BLESearchMotionCoreTests: XCTestCase {
    func testStraightPathStaysRoughlyLinear() {
        let tracker = IndoorMotionTracker()
        tracker.reset()
        tracker.debugAdvance(steps: 8, headingDegrees: 0) // Norden
        let pts = tracker.path
        XCTAssertGreaterThan(pts.count, 2)
        let last = pts.last!
        XCTAssertGreaterThan(last.y, 4)
        XCTAssertLessThan(abs(last.x), 1.2)
    }

    func testRightTurnIsVisibleOnPath() {
        let tracker = IndoorMotionTracker()
        tracker.reset()
        tracker.debugAdvance(steps: 5, headingDegrees: 0)
        tracker.debugAdvance(steps: 5, headingDegrees: 90)
        let snap = SearchPathReconstructor.snapshot(from: tracker.path, previousViewport: nil, followSoftly: false)
        XCTAssertGreaterThan(snap.pathLengthMeters, 5)
        guard let first = snap.smoothedPolyline.first, let last = snap.smoothedPolyline.last else {
            return XCTFail("polyline empty")
        }
        // Nach Rechtskurve: Osten (x+) und Norden (y+)
        XCTAssertGreaterThan(last.x, first.x + 2)
        XCTAssertGreaterThan(last.y, first.y + 2)
    }

    func testUTurnCreatesReversal() {
        let tracker = IndoorMotionTracker()
        tracker.reset()
        tracker.debugAdvance(steps: 6, headingDegrees: 0)
        let midY = tracker.currentY
        tracker.debugAdvance(steps: 6, headingDegrees: 180)
        let snap = SearchPathReconstructor.snapshot(from: tracker.path, previousViewport: nil, followSoftly: false)
        XCTAssertGreaterThan(snap.smoothedPolyline.count, 3)
        // Zurück Richtung Start: y wieder kleiner als Mid-Peak
        XCTAssertLessThan(tracker.currentY, midY - 1)
    }

    func testStandstillDoesNotInventMotion() {
        let tracker = IndoorMotionTracker()
        tracker.reset()
        tracker.debugAdvance(steps: 3, headingDegrees: 45)
        let before = tracker.path.count
        let x = tracker.currentX
        let y = tracker.currentY
        // Heading-Rauschen ohne Schritte
        tracker.ingestExternalHeading(47)
        tracker.ingestExternalHeading(44)
        tracker.ingestExternalHeading(46)
        XCTAssertEqual(tracker.path.count, before)
        XCTAssertEqual(tracker.currentX, x, accuracy: 0.001)
        XCTAssertEqual(tracker.currentY, y, accuracy: 0.001)
    }

    func testHeatmapFollowsReconstructedPath() {
        let tracker = IndoorMotionTracker()
        tracker.reset()
        tracker.debugAdvance(steps: 4, headingDegrees: 0)
        tracker.debugAdvance(steps: 4, headingDegrees: 90)
        let snap = SearchPathReconstructor.snapshot(from: tracker.path, previousViewport: nil, followSoftly: false)
        var measurements: [BLEMeasurement] = []
        for (i, p) in snap.points.enumerated() {
            measurements.append(
                BLEMeasurement(
                    timestamp: Date().addingTimeInterval(Double(i)),
                    rawRssi: -55 - i,
                    smoothedRssi: Double(-55 - i),
                    relativeX: p.x,
                    relativeY: p.y,
                    positionQuality: .high
                )
            )
        }
        let heat = HeatmapPlacementEngine.build(
            measurements: measurements,
            viewport: snap.viewport,
            pathPolyline: snap.smoothedPolyline
        )
        XCTAssertFalse(heat.trail.isEmpty)
        let filled = heat.cells.compactMap { $0 }.count
        XCTAssertGreaterThan(filled, 0)
        // Trail sollte entlang des Pfads liegen, nicht nur am Ursprung
        if let last = heat.trail.last, let first = heat.trail.first {
            XCTAssertGreaterThan(hypot(last.x - first.x, last.y - first.y), 2)
        }
    }

    func testViewportKeepsPathInViewWithoutJumping() {
        var pts: [BLEPathPoint] = []
        for i in 0..<12 {
            pts.append(BLEPathPoint(x: Double(i) * 0.8, y: Double(i) * 0.1, headingDegrees: 80))
        }
        let first = SearchPathReconstructor.snapshot(from: pts, previousViewport: nil, followSoftly: false)
        var extended = pts
        extended.append(BLEPathPoint(x: 10.5, y: 1.4, headingDegrees: 80))
        let second = SearchPathReconstructor.snapshot(
            from: extended,
            previousViewport: first.viewport,
            followSoftly: true
        )
        let dx = abs(second.viewport.centerX - first.viewport.centerX)
        let dy = abs(second.viewport.centerY - first.viewport.centerY)
        // Soft-follow: kleine Bewegung, kein harter Sprung über die gesamte Strecke
        XCTAssertLessThan(dx, 4)
        XCTAssertLessThan(dy, 4)
        XCTAssertGreaterThan(second.viewport.spanMeters, 8)
    }

    func testPathLengthMatchesWalkedDistanceRoughly() {
        let tracker = IndoorMotionTracker()
        tracker.reset()
        tracker.debugAdvance(steps: 10, headingDegrees: 0)
        let snap = SearchPathReconstructor.snapshot(from: tracker.path, previousViewport: nil, followSoftly: false)
        let expected = 10 * BLEPathConfig.stepLengthMeters
        XCTAssertEqual(snap.pathLengthMeters, expected, accuracy: expected * 0.25)
    }

    func testSurfaceModeLabels() {
        XCTAssertEqual(BLESearchSurfaceMode.relative.label, "Relativ")
        XCTAssertEqual(BLESearchSurfaceMode.map.label, "Karte")
    }

    func testMapRegionFitsTightlyAroundShortPath() {
        let origin = CLLocation(latitude: 52.52, longitude: 13.405)
        // Kurzer L-Pfad ~5 m × 5 m
        let enu: [(x: Double, y: Double)] = [
            (0, 0), (0, 3), (0, 5), (2, 5), (5, 5)
        ]
        let region = OutdoorMapTracker.fittedRegion(
            enuPoints: enu,
            currentENU: (5, 5),
            origin: origin,
            previous: nil,
            softFollow: false
        )
        let mPerDegLat = 111_320.0
        let spanMeters = region.span.latitudeDelta * mPerDegLat
        // Eng am Weg — nicht die alten ~90 m Stadtblick-Zoomstufe
        XCTAssertLessThan(spanMeters, 45)
        XCTAssertGreaterThanOrEqual(spanMeters, BLEPathConfig.mapMinSpanMeters * 0.9)
    }

    func testMapHeatUsesRelativeNotRawGPS() {
        let origin = CLLocation(latitude: 52.52, longitude: 13.405)
        let path = [
            BLEPathPoint(x: 0, y: 0),
            BLEPathPoint(x: 0, y: 4),
            BLEPathPoint(x: 3, y: 4)
        ]
        // Messungen mit absichtlich falschen GPS-Koordinaten (Indoor-Rauschen)
        let noisyGPS = BLEMeasurement(
            timestamp: Date(),
            rawRssi: -60,
            smoothedRssi: -60,
            latitude: 52.53, // weit weg
            longitude: 13.42,
            relativeX: 0,
            relativeY: 4,
            positionQuality: .low
        )
        let model = OutdoorMapTracker.model(
            origin: origin,
            path: path,
            smoothedPolyline: path.map { (x: $0.x, y: $0.y) },
            measurements: [noisyGPS],
            lastGPS: origin,
            previousRegion: nil,
            softFollow: false
        )
        XCTAssertEqual(model.heatSamples.count, 1)
        // Heat muss am relativen Punkt liegen, nicht am GPS-Rauschen
        let heat = model.heatSamples[0].coord
        XCTAssertEqual(heat.latitude, origin.coordinate.latitude + 4 / 111_320.0, accuracy: 0.00005)
        XCTAssertLessThan(abs(heat.longitude - origin.coordinate.longitude), 0.00005)
    }

    func testGPSFusionIgnoredWhenAccuracyPoor() {
        let tracker = IndoorMotionTracker()
        tracker.reset()
        tracker.debugAdvance(steps: 3, headingDegrees: 0)
        let beforeX = tracker.currentX
        let beforeY = tracker.currentY
        // Indoor-typische GPS-Genauigkeit darf den Pfad nicht verbiegen
        tracker.ingestGPSDelta(east: 25, north: -18, accuracy: 18)
        XCTAssertEqual(tracker.currentX, beforeX, accuracy: 0.001)
        XCTAssertEqual(tracker.currentY, beforeY, accuracy: 0.001)
    }
}
