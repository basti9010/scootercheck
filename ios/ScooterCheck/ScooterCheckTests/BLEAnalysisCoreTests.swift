import XCTest
@testable import ScooterCheck

final class BLEAnalysisCoreTests: XCTestCase {

    // 1. Name ändert sich, UUIDs + Manufacturer bleiben → hohe Ähnlichkeit
    func testFingerprintHighSimilarityDespiteNameChange() {
        let base = BLEDeviceFingerprint(
            localName: "NB-OLD",
            manufacturerDataHex: "4C0011223344",
            manufacturerId: 0x004C,
            serviceUUIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E", "FFE0"],
            serviceDataHexByUUID: ["FFE0": "AABB"],
            advertisingStructureKey: "NMS2DTC",
            txPower: -8,
            isConnectable: true
        )
        let renamed = BLEDeviceFingerprint(
            localName: "NB-NEW-NAME",
            manufacturerDataHex: "4C0011223344",
            manufacturerId: 0x004C,
            serviceUUIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E", "FFE0"],
            serviceDataHexByUUID: ["FFE0": "AABB"],
            advertisingStructureKey: "NMS2DTC",
            txPower: -8,
            isConnectable: true
        )
        let match = BLEFingerprintService.compare(base, renamed)
        XCTAssertEqual(match.similarity, .high)
        XCTAssertGreaterThanOrEqual(match.score, 70)
        let nameFactor = match.factors.first { $0.id == "name" }
        XCTAssertEqual(nameFactor?.matched, false)
        XCTAssertEqual(match.factors.first { $0.id == "mfg" }?.matched, true)
        XCTAssertEqual(match.factors.first { $0.id == "uuid" }?.matched, true)
    }

    func testFingerprintWorksWithEmptyName() {
        let a = BLEDeviceFingerprint(
            localName: nil,
            manufacturerDataHex: "ABCD1234",
            serviceUUIDs: ["FFE0"],
            advertisingStructureKey: "-MS1--C"
        )
        let b = BLEDeviceFingerprint(
            localName: nil,
            manufacturerDataHex: "ABCD1234",
            serviceUUIDs: ["FFE0"],
            advertisingStructureKey: "-MS1--C"
        )
        let match = BLEFingerprintService.compare(a, b)
        XCTAssertTrue(match.similarity == .high || match.similarity == .medium)
    }

    // 2. Timeline: Signal verloren / wiedergefunden als Events
    func testTimelineRecordsLostAndRefoundNotEveryRssi() {
        var timeline = BLESearchTimeline()
        XCTAssertTrue(timeline.append(BLESearchEvent(type: .searchStarted, title: "Suche gestartet"), minInterval: 0))
        XCTAssertTrue(timeline.append(BLESearchEvent(type: .signalLost, title: "Signal verloren"), minInterval: 0))
        // Debounce gleicher Typ
        XCTAssertFalse(timeline.append(
            BLESearchEvent(
                timestamp: Date().addingTimeInterval(0.2),
                type: .signalLost,
                title: "Signal verloren"
            ),
            minInterval: 1.2
        ))
        XCTAssertTrue(timeline.append(
            BLESearchEvent(
                timestamp: Date().addingTimeInterval(2),
                type: .signalRefound,
                title: "Signal wiedergefunden"
            ),
            minInterval: 0
        ))
        XCTAssertEqual(timeline.events.count, 3)
        XCTAssertEqual(timeline.events.map(\.type), [.searchStarted, .signalLost, .signalRefound])
    }

    // 3. Bewegungshinweis: stilles Handy + starker RSSI-Drift
    func testMovementHintRequiresSustainedChange() {
        var analyzer = BLEMovementAnalyzer()
        let t0 = Date()
        // Baseline etablieren (Handy still ≥ 4 s)
        for i in 0..<6 {
            let hint = analyzer.evaluate(
                now: t0.addingTimeInterval(Double(i) * 1.0),
                phoneSpeed: 0.05,
                accuracy: 8,
                smoothedRssi: -60,
                signalLostRecently: false,
                heatmapCentroidShiftMeters: 0
            )
            XCTAssertFalse(hint.active)
        }
        // Kleine Schwankung → kein Hinweis
        let small = analyzer.evaluate(
            now: t0.addingTimeInterval(8),
            phoneSpeed: 0.05,
            accuracy: 8,
            smoothedRssi: -62,
            signalLostRecently: false,
            heatmapCentroidShiftMeters: 0
        )
        XCTAssertFalse(small.active)

        // Dauerhafte große Änderung bei stillstehendem Handy
        _ = analyzer.evaluate(
            now: t0.addingTimeInterval(10),
            phoneSpeed: 0.05,
            accuracy: 8,
            smoothedRssi: -76,
            signalLostRecently: false,
            heatmapCentroidShiftMeters: 0
        )
        let hint = analyzer.evaluate(
            now: t0.addingTimeInterval(10 + BLEMovementAnalyzer.minDuration + 1),
            phoneSpeed: 0.05,
            accuracy: 8,
            smoothedRssi: -78,
            signalLostRecently: false,
            heatmapCentroidShiftMeters: 5
        )
        XCTAssertTrue(hint.active)
        XCTAssertFalse(hint.explanation.isEmpty)
    }

    func testMovementHintIgnoresWhenPhoneMoving() {
        var analyzer = BLEMovementAnalyzer()
        let t0 = Date()
        let hint = analyzer.evaluate(
            now: t0.addingTimeInterval(20),
            phoneSpeed: 1.4,
            accuracy: 6,
            smoothedRssi: -50,
            signalLostRecently: false,
            heatmapCentroidShiftMeters: 10
        )
        XCTAssertFalse(hint.active)
    }

    // 4 / 5. Direction trend when moving toward stronger signal
    func testDirectionTrendRequiresPathAndGain() {
        var service = BLEDirectionTrendService()
        let t0 = Date()
        // Zu wenig Bewegung
        service.ingest(date: t0, x: 0, y: 0, rssi: -80)
        service.ingest(date: t0.addingTimeInterval(2), x: 0.5, y: 0.2, rssi: -79)
        XCTAssertFalse(service.evaluate(at: t0.addingTimeInterval(3)).reliable)

        // Lauf nach Norden mit steigendem RSSI
        for i in 0..<12 {
            let t = t0.addingTimeInterval(Double(i) * 1.2)
            let y = Double(i) * 0.8
            let rssi = -80.0 + Double(i) * 1.2
            service.ingest(date: t, x: 0.1 * Double(i), y: y, rssi: rssi)
        }
        let trend = service.evaluate(at: t0.addingTimeInterval(14))
        XCTAssertTrue(trend.reliable)
        XCTAssertNotNil(trend.headingDegrees)
        XCTAssertTrue(trend.label.contains("Bewegungsrichtung"))
    }

    // 6. Suchraster füllt sich
    func testSearchGridFillsAndReportsCoverage() {
        var measurements: [BLEMeasurement] = []
        let t = Date()
        for i in 0..<20 {
            let x = Double(i % 5) * 3.0
            let y = Double(i / 5) * 3.0
            measurements.append(BLEMeasurement(
                timestamp: t,
                rawRssi: -60,
                smoothedRssi: -60,
                relativeX: x,
                relativeY: y,
                positionQuality: .high
            ))
        }
        // Mehrere Samples pro Zelle
        for i in 0..<20 {
            let x = Double(i % 5) * 3.0
            let y = Double(i / 5) * 3.0
            measurements.append(BLEMeasurement(
                timestamp: t,
                rawRssi: -58,
                smoothedRssi: -58,
                relativeX: x,
                relativeY: y,
                positionQuality: .high
            ))
            measurements.append(BLEMeasurement(
                timestamp: t,
                rawRssi: -59,
                smoothedRssi: -59,
                relativeX: x,
                relativeY: y,
                positionQuality: .high
            ))
        }
        let grid = BLESearchGrid.build(from: measurements)
        XCTAssertNotNil(grid.area)
        XCTAssertTrue(grid.area?.isMeaningful == true)
        XCTAssertNotNil(grid.coverageRatio)
        XCTAssertGreaterThan(grid.coverageRatio ?? 0, 0.1)
        XCTAssertNotNil(grid.coveragePercentText)
        let statuses = Set(grid.cells.map(\.status))
        XCTAssertTrue(statuses.contains(.partial) || statuses.contains(.scanned))
    }

    func testOpenTerrainHasNoFakeCoveragePercent() {
        let m = BLEMeasurement(
            timestamp: Date(),
            rawRssi: -70,
            smoothedRssi: -70,
            relativeX: 0,
            relativeY: 0,
            positionQuality: .high
        )
        let grid = BLESearchGrid.build(from: [m])
        XCTAssertNil(grid.coveragePercentText)
    }

    // 7. Multi-device: Status unabhängig (Fingerprint-Vergleich)
    func testFingerprintIndependenceAcrossDevices() {
        let a = BLEDeviceFingerprint(
            localName: "A",
            manufacturerDataHex: "1111",
            serviceUUIDs: ["AAAA"]
        )
        let b = BLEDeviceFingerprint(
            localName: "B",
            manufacturerDataHex: "2222",
            serviceUUIDs: ["BBBB"]
        )
        let matchAB = BLEFingerprintService.compare(a, b)
        let matchAA = BLEFingerprintService.compare(a, a)
        XCTAssertEqual(matchAA.similarity, .high)
        XCTAssertNotEqual(matchAB.similarity, .high)
    }

    // 8. ObservedBLEDevice bleibt userSelected / keine Scooter-Persistenz-Grenze
    func testObservedDeviceIsNotValidatedScooter() {
        let fp = BLEDeviceFingerprint(localName: "TV-Remote", manufacturerDataHex: "99AA")
        let observed = ObservedBLEDevice(
            id: UUID(),
            displayName: "TV-Remote",
            fingerprint: fp,
            rawRssi: -55,
            smoothedRssi: -56,
            trend: .stable,
            isVisible: true,
            lastSeenAt: Date(),
            similarity: nil,
            userSelected: true
        )
        XCTAssertTrue(observed.userSelected)
        XCTAssertEqual(ValidatedScooterBoundary.note.contains("keine Scooter"), true)
    }

    func testSignalHistoryWindowAndMarkers() {
        var history = BLESignalHistory()
        history.windowSeconds = 30
        let t0 = Date()
        for i in 0..<40 {
            history.append(smoothed: -70 + Double(i) * 0.2, raw: -70, at: t0.addingTimeInterval(Double(i)))
        }
        history.addMarker(.signalLost, at: t0.addingTimeInterval(20))
        history.addMarker(.signalRefound, at: t0.addingTimeInterval(25))
        XCTAssertFalse(history.points.isEmpty)
        XCTAssertLessThanOrEqual(history.points.count, 240)
        // Alte Punkte außerhalb Fenster entfernt
        XCTAssertTrue(history.points.allSatisfy { t0.addingTimeInterval(40).timeIntervalSince($0.timestamp) <= 31 })
        XCTAssertEqual(history.markers.count, 2)
    }

    func testSimilarityLabelsAvoidCertainty() {
        XCTAssertTrue(BLEFingerprintSimilarity.high.label.contains("Übereinstimmung"))
        XCTAssertFalse(BLEFingerprintSimilarity.high.label.lowercased().contains("sicher"))
        XCTAssertFalse(BLEFingerprintSimilarity.high.label.lowercased().contains("dasselbe gerät ist"))
    }
}
