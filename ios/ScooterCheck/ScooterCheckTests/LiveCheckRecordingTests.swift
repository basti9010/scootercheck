import XCTest
@testable import ScooterCheck

final class LiveCheckRecordingTests: XCTestCase {

    func testAppendUpdatesPeaksAndSampleCount() {
        var recording = LiveCheckRecording()
        var snap = LiveTelemetrySnapshot()
        snap.speedKmh = 18.5
        snap.powerW = 420
        snap.controllerTempC = 31.2
        snap.batteryTempC = 28.0
        recording.append(snap)

        snap.speedKmh = 27.0
        snap.powerW = 900
        snap.controllerTempC = 36.0
        snap.batteryTempC = 29.5
        recording.append(snap)

        XCTAssertEqual(recording.sampleCount, 2)
        XCTAssertEqual(recording.peakSpeedKmh ?? 0, 27.0, accuracy: 0.01)
        XCTAssertEqual(recording.peakPowerW ?? 0, 900, accuracy: 0.5)
        XCTAssertEqual(recording.maxControllerTempC ?? 0, 36.0, accuracy: 0.05)
        XCTAssertEqual(recording.maxBatteryTempC ?? 0, 29.5, accuracy: 0.05)
        XCTAssertTrue(recording.summaryLine.contains("2 Punkte"))
    }

    func testCsvContainsHeaderAndRows() {
        var recording = LiveCheckRecording(serialDisplay: "1EFHE2515C0440")
        var snap = LiveTelemetrySnapshot()
        snap.speedKmh = 12.3
        snap.batteryPercent = 77
        snap.voltageV = 51.2
        recording.append(snap)
        let csv = recording.csvString()
        XCTAssertTrue(csv.hasPrefix("timestamp_iso,speed_kmh"))
        XCTAssertTrue(csv.contains("12.300"))
        XCTAssertTrue(csv.contains("77"))
        XCTAssertTrue(csv.contains("51.200"))
    }

    func testMaxSamplesCap() {
        var recording = LiveCheckRecording()
        var snap = LiveTelemetrySnapshot()
        snap.speedKmh = 1
        for _ in 0..<(LiveCheckRecording.maxSamples + 10) {
            recording.append(snap)
        }
        XCTAssertEqual(recording.sampleCount, LiveCheckRecording.maxSamples)
    }

    func testCodableRoundTrip() throws {
        var recording = LiveCheckRecording(protocolNumber: "SC-TEST", serialDisplay: "1K1DA…")
        var snap = LiveTelemetrySnapshot()
        snap.currentA = -2.5
        snap.powerW = 100
        recording.append(snap)
        recording.endedAt = Date()
        let data = try JSONEncoder().encode(recording)
        let decoded = try JSONDecoder().decode(LiveCheckRecording.self, from: data)
        XCTAssertEqual(decoded.protocolNumber, "SC-TEST")
        XCTAssertEqual(decoded.sampleCount, 1)
        XCTAssertEqual(decoded.samples.first?.currentA ?? 0, -2.5, accuracy: 0.01)
        XCTAssertFalse(decoded.events.isEmpty)
    }

    func testPeakAndThresholdEvents() {
        var recording = LiveCheckRecording()
        var snap = LiveTelemetrySnapshot()
        snap.speedKmh = 18
        snap.powerW = 400
        snap.controllerTempC = 40
        recording.append(snap)
        XCTAssertTrue(recording.events.contains { $0.kind == .newPeakSpeed })
        XCTAssertTrue(recording.alarmEvents.isEmpty)

        snap.speedKmh = 27
        snap.powerW = 1_500
        snap.controllerTempC = 58
        recording.append(snap)
        XCTAssertEqual(recording.peakSpeedKmh ?? 0, 27, accuracy: 0.01)
        XCTAssertEqual(recording.peakPowerW ?? 0, 1_500, accuracy: 0.5)
        XCTAssertTrue(recording.events.contains { $0.kind == .thresholdSpeed })
        XCTAssertTrue(recording.events.contains { $0.kind == .thresholdPower })
        XCTAssertTrue(recording.events.contains { $0.kind == .thresholdControllerTemp })
        XCTAssertEqual(recording.alarmEvents.count, 3)

        // Schwellen nur einmal
        snap.speedKmh = 30
        recording.append(snap)
        XCTAssertEqual(recording.events.filter { $0.kind == .thresholdSpeed }.count, 1)
        XCTAssertTrue(recording.summaryLine.contains("Alarm"))
    }

    func testLiveAlertsForHotController() {
        var recording = LiveCheckRecording()
        var snap = LiveTelemetrySnapshot()
        snap.controllerTempC = 72
        recording.append(snap)
        let alerts = recording.liveAlerts(for: snap)
        XCTAssertTrue(alerts.contains { $0.contains("Controller") })
    }

    func testCsvIncludesEventsSection() {
        var recording = LiveCheckRecording()
        var snap = LiveTelemetrySnapshot()
        snap.speedKmh = 26
        recording.append(snap)
        let csv = recording.csvString()
        XCTAssertTrue(csv.contains("# events"))
        XCTAssertTrue(csv.contains("thresholdSpeed") || csv.contains("newPeakSpeed"))
    }

    func testDecodeLegacyWithoutEvents() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "startedAt": "2026-11-16T12:00:00Z",
          "samples": [],
          "peakSpeedKmh": 12.5
        }
        """.data(using: .utf8)!
        // Match ProtocolHistoryStore persistence (ISO-8601), not the default Date decoder.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LiveCheckRecording.self, from: json)
        XCTAssertEqual(decoded.events.count, 0)
        XCTAssertEqual(decoded.peakSpeedKmh ?? 0, 12.5, accuracy: 0.01)
    }
}
