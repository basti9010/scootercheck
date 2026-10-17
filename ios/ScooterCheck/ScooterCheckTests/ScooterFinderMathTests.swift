import XCTest
@testable import ScooterCheck

final class ScooterFinderMathTests: XCTestCase {
    func testEmaConvergesTowardNewSample() {
        let a = ScooterFinderMath.ema(previous: -80, sample: -60, alpha: 0.5)
        XCTAssertEqual(a, -70, accuracy: 0.001)
    }

    func testMedianOddEven() {
        XCTAssertEqual(ScooterFinderMath.median([-70, -60, -80]), -70)
        XCTAssertEqual(ScooterFinderMath.median([-70, -60]), -65)
    }

    func testSmoothRssiUsesWindow() {
        let history = [-90, -88, -70, -68, -66, -64, -62]
        let smooth = ScooterFinderMath.smoothRssi(history: history)
        XCTAssertNotNil(smooth)
        XCTAssertGreaterThan(smooth!, -75)
    }

    func testRelativeArrowNormalization() {
        XCTAssertEqual(
            ScooterFinderMath.relativeArrowDegrees(worldBearing: 10, deviceHeading: 350),
            20,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ScooterFinderMath.relativeArrowDegrees(worldBearing: 0, deviceHeading: 90),
            -90,
            accuracy: 0.01
        )
    }

    func testEstimateBearingNortheastTrend() {
        // Start south-west weak → move NE with stronger RSSI
        let base = Date()
        func sample(t: TimeInterval, lat: Double, lon: Double, rssi: Double) -> FinderSample {
            FinderSample(
                timestamp: base.addingTimeInterval(t),
                latitude: lat,
                longitude: lon,
                horizontalAccuracy: 8,
                heading: 45,
                headingAccuracy: 5,
                rssiRaw: Int(rssi),
                rssiSmoothed: rssi,
                stepCount: nil,
                distanceMeters: nil
            )
        }
        // ~1m north/east steps around 52.5N 13.4E
        let lat0 = 52.5200
        let lon0 = 13.4050
        let dLat = 4.0 / 111_320.0
        let dLon = 4.0 / (111_320.0 * cos(lat0 * .pi / 180))
        let samples = [
            sample(t: 0, lat: lat0, lon: lon0, rssi: -78),
            sample(t: 2, lat: lat0 + dLat, lon: lon0 + dLon, rssi: -73),
            sample(t: 4, lat: lat0 + 2 * dLat, lon: lon0 + 2 * dLon, rssi: -67),
            sample(t: 6, lat: lat0 + 3 * dLat, lon: lon0 + 3 * dLon, rssi: -62),
            sample(t: 8, lat: lat0 + 4 * dLat, lon: lon0 + 4 * dLon, rssi: -58),
        ]
        let estimate = ScooterFinderMath.estimateStrongerBearing(from: samples)
        XCTAssertNotNil(estimate)
        // Northeast ≈ 45°
        XCTAssertEqual(estimate!.bearing, 45, accuracy: 25)
        XCTAssertGreaterThan(estimate!.confidence, 0.2)
    }

    func testSignalTier() {
        XCTAssertEqual(FinderSignalTier.from(rssi: -45), .veryNear)
        XCTAssertEqual(FinderSignalTier.from(rssi: -55), .veryStrong)
        XCTAssertEqual(FinderSignalTier.from(rssi: -65), .strong)
        XCTAssertEqual(FinderSignalTier.from(rssi: -75), .medium)
        XCTAssertEqual(FinderSignalTier.from(rssi: -90), .weak)
    }

    func testPathLengthIncreasesWithMovement() {
        let base = Date()
        let lat0 = 52.52
        let lon0 = 13.40
        let dLat = 5.0 / 111_320.0
        let samples = (0..<5).map { i in
            FinderSample(
                timestamp: base.addingTimeInterval(Double(i)),
                latitude: lat0 + Double(i) * dLat,
                longitude: lon0,
                horizontalAccuracy: 5,
                heading: 0,
                headingAccuracy: 5,
                rssiRaw: -70,
                rssiSmoothed: -70,
                stepCount: nil,
                distanceMeters: nil
            )
        }
        let path = ScooterFinderMath.pathLengthMeters(samples)
        XCTAssertGreaterThan(path, 15)
    }

    func testStableListIgnoresSmallRssiFlicker() {
        let a = UUID()
        let b = UUID()
        let t0 = Date()
        let first = BleScanListStabilizer.reconcile(
            previousOrder: [],
            items: [
                .init(id: a, rssi: -60, isStale: false),
                .init(id: b, rssi: -70, isStale: false),
            ],
            lastReorderAt: .distantPast,
            now: t0
        )
        XCTAssertEqual(first.order, [a, b])

        // Kleiner RSSI-Tausch (−58 vs −60) darf die Reihenfolge nicht drehen.
        let flickered = BleScanListStabilizer.reconcile(
            previousOrder: first.order,
            items: [
                .init(id: a, rssi: -62, isStale: false),
                .init(id: b, rssi: -58, isStale: false),
            ],
            lastReorderAt: first.reorderAt,
            now: t0.addingTimeInterval(2)
        )
        XCTAssertEqual(flickered.order, [a, b])
    }

    func testStableListReordersWhenHysteresisExceeded() {
        let a = UUID()
        let b = UUID()
        let t0 = Date()
        let first = BleScanListStabilizer.reconcile(
            previousOrder: [],
            items: [
                .init(id: a, rssi: -60, isStale: false),
                .init(id: b, rssi: -70, isStale: false),
            ],
            lastReorderAt: .distantPast,
            now: t0
        )
        let reordered = BleScanListStabilizer.reconcile(
            previousOrder: first.order,
            items: [
                .init(id: a, rssi: -72, isStale: false),
                .init(id: b, rssi: -55, isStale: false),
            ],
            lastReorderAt: first.reorderAt,
            now: t0.addingTimeInterval(2)
        )
        XCTAssertEqual(reordered.order, [b, a])
    }
}
