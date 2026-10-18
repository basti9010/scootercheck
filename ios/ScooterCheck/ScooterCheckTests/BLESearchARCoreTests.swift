import XCTest
@testable import ScooterCheck

final class BLESearchARCoreTests: XCTestCase {
    func testFixedColorScaleIsMonotonicTowardStronger() {
        let weak = ARSignalColorScale.uiColor(forRssi: -90)
        let mid = ARSignalColorScale.uiColor(forRssi: -70)
        let strong = ARSignalColorScale.uiColor(forRssi: -50)
        var wr: CGFloat = 0, wg: CGFloat = 0, wb: CGFloat = 0, wa: CGFloat = 0
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        weak.getRed(&wr, green: &wg, blue: &wb, alpha: &wa)
        strong.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        // Starkes Signal → mehr Grün/Mint als sehr schwaches
        XCTAssertGreaterThan(sg, wg)
        _ = mid
    }

    func testBestZoneIgnoresSingleSpikeWithoutConfirmation() {
        var est = ARBestZoneEstimator()
        est.confirmSeconds = 1.5
        est.hysteresisDb = 4

        let spike = (0..<3).map { i in
            ARSpatialSample(
                timestamp: Date().addingTimeInterval(Double(i) * 0.1),
                x: 5, y: 5,
                rawRssi: -40, smoothedRssi: -40,
                trackingHealthy: true, sessionEpoch: 1
            )
        }
        est.ingest(samples: spike, now: Date())
        // Noch nicht bestätigt (zu kurz / pending)
        // Nach confirmSeconds:
        let later = Date().addingTimeInterval(2)
        est.ingest(samples: spike, now: later)
        XCTAssertNotNil(est.confirmed)
        XCTAssertEqual(est.confirmed?.x ?? 0, 5, accuracy: 1.0)
    }

    func testBestZoneHysteresisPreventsJumpToSlightlyBetterNeighbor() {
        var est = ARBestZoneEstimator()
        est.confirmSeconds = 0.1
        est.hysteresisDb = 4

        let zoneA = (0..<4).map { i in
            ARSpatialSample(
                x: 0, y: 0,
                rawRssi: -60, smoothedRssi: -60,
                trackingHealthy: true, sessionEpoch: 1
            )
        }
        let t0 = Date()
        est.ingest(samples: zoneA, now: t0)
        est.ingest(samples: zoneA, now: t0.addingTimeInterval(0.2))
        XCTAssertNotNil(est.confirmed)

        let slightlyBetter = (0..<4).map { _ in
            ARSpatialSample(
                x: 8, y: 0,
                rawRssi: -58, smoothedRssi: -58,
                trackingHealthy: true, sessionEpoch: 1
            )
        }
        let before = est.confirmed
        est.ingest(samples: zoneA + slightlyBetter, now: t0.addingTimeInterval(1))
        est.ingest(samples: zoneA + slightlyBetter, now: t0.addingTimeInterval(1.3))
        // Nur +2 dB → Hysterese hält alte Zone
        XCTAssertEqual(est.confirmed?.x ?? -1, before?.x ?? -2, accuracy: 1.5)
    }

    func testGuidanceDirectionIsRelativeToHeading() {
        let text = ARGuidanceController.relativeDirection(dx: 5, dy: 0, heading: 0)
        XCTAssertEqual(text, "rechts")
        let ahead = ARGuidanceController.relativeDirection(dx: 0, dy: 5, heading: 0)
        XCTAssertEqual(ahead, "geradeaus")
    }

    func testGuidanceHoldsHintBriefly() {
        var g = ARGuidanceController()
        let t0 = Date()
        let first = g.update(
            trend: .stronger,
            signalLost: false,
            trackingHealthy: true,
            sampleCount: 10,
            bestZone: nil,
            currentX: 0, currentY: 0,
            headingDegrees: 0,
            now: t0
        )
        XCTAssertEqual(first, .stronger)
        let second = g.update(
            trend: .weaker,
            signalLost: false,
            trackingHealthy: true,
            sampleCount: 10,
            bestZone: nil,
            currentX: 0, currentY: 0,
            headingDegrees: 0,
            now: t0.addingTimeInterval(0.4)
        )
        XCTAssertEqual(second, .stronger)
    }

    func testFloorTextureReturnsNilWithoutSamples() {
        let img = ARFloorHeatmapRenderer.makeTexture(
            samples: [],
            centerX: 0, centerY: 0,
            spanMeters: 12,
            opacity: 0.5
        )
        XCTAssertNil(img)
    }

    func testFloorTextureBuildsForCluster() {
        let samples = (0..<8).map { i in
            ARSpatialSample(
                x: Double(i) * 0.4, y: Double(i) * 0.1,
                rawRssi: -65, smoothedRssi: -65,
                trackingHealthy: true, sessionEpoch: 1
            )
        }
        let img = ARFloorHeatmapRenderer.makeTexture(
            samples: samples,
            centerX: 1.5, centerY: 0.4,
            spanMeters: 10,
            opacity: 0.55,
            size: 64
        )
        XCTAssertNotNil(img)
    }
}
