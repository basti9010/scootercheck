import XCTest
@testable import ScooterCheck

final class BLESearchCoreTests: XCTestCase {
    func testProcessorSmoothsOutliers() {
        var p = BLESignalProcessor()
        // Stabile Werte, dann Ausreißer
        for v in [-70, -69, -71, -70, -68] {
            _ = p.ingest(rawRssi: v)
        }
        let before = p.smoothed
        _ = p.ingest(rawRssi: -40) // Spike
        let after = p.smoothed
        XCTAssertNotNil(before)
        XCTAssertNotNil(after)
        // Darf nicht voll auf den Spike springen
        XCTAssertLessThan(abs((after ?? 0) - (before ?? 0)), 12)
    }

    func testSignalClassOrdering() {
        XCTAssertEqual(BLESignalClass.from(smoothedRssi: -45, lost: false), .veryStrong)
        XCTAssertEqual(BLESignalClass.from(smoothedRssi: -65, lost: false), .medium)
        XCTAssertEqual(BLESignalClass.from(smoothedRssi: -90, lost: false), .veryWeak)
        XCTAssertEqual(BLESignalClass.from(smoothedRssi: -50, lost: true), .lost)
    }

    func testTrendStrongerWithRisingWindow() {
        var p = BLESignalProcessor()
        let t0 = Date()
        for i in 0..<8 {
            _ = p.ingest(rawRssi: -80, at: t0.addingTimeInterval(Double(i) * 0.3))
        }
        for i in 0..<8 {
            _ = p.ingest(rawRssi: -58, at: t0.addingTimeInterval(3.0 + Double(i) * 0.3))
        }
        let trend = p.trend(at: t0.addingTimeInterval(5.5))
        XCTAssertEqual(trend, .stronger)
    }

    func testHeatmapLeavesUnknownCellsEmpty() {
        let m = BLEMeasurement(
            timestamp: Date(),
            rawRssi: -60,
            smoothedRssi: -60,
            relativeX: 0,
            relativeY: 0,
            positionQuality: .high
        )
        let snap = BLEHeatmapProcessor.build(from: [m])
        let filled = snap.cells.compactMap { $0 }.count
        XCTAssertGreaterThan(filled, 0)
        XCTAssertLessThan(filled, snap.cells.count) // nicht alles eingefärbt
    }

    func testHeatmapStrongerNearMeasurement() {
        let strong = BLEMeasurement(
            timestamp: Date(),
            rawRssi: -48,
            smoothedRssi: -48,
            relativeX: 0,
            relativeY: 0,
            positionQuality: .high
        )
        let weak = BLEMeasurement(
            timestamp: Date(),
            rawRssi: -88,
            smoothedRssi: -88,
            relativeX: 12,
            relativeY: 0,
            positionQuality: .high
        )
        let snap = BLEHeatmapProcessor.build(from: [strong, weak])
        XCTAssertNotNil(snap.strongestCell)
        // Stärkste Zelle sollte näher an (0,0) liegen als an (12,0)
        if let s = snap.strongestCell {
            let x = snap.originEast + (Double(s.col) + 0.5) * snap.cellSize
            XCTAssertLessThan(abs(x), 6)
        }
    }

    func testPositionQualityWeights() {
        XCTAssertEqual(BLEPositionQuality.from(accuracyMeters: 5), .high)
        XCTAssertEqual(BLEPositionQuality.from(accuracyMeters: 20), .medium)
        XCTAssertEqual(BLEPositionQuality.from(accuracyMeters: 50), .low)
        XCTAssertGreaterThan(BLEPositionQuality.high.weight, BLEPositionQuality.low.weight)
    }
}
