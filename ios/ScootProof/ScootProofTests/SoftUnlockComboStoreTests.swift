import XCTest
@testable import ScootProof

@MainActor
final class SoftUnlockComboStoreTests: XCTestCase {

    private let testSerial = "1CGBSTORETEST01"

    override func setUp() {
        super.setUp()
        SoftUnlockComboStore.delete(forSerial: testSerial)
    }

    override func tearDown() {
        SoftUnlockComboStore.delete(forSerial: testSerial)
        super.tearDown()
    }

    func testSaveLoadRoundTripPerSerial() {
        let combo = SoftUnlockCombo(
            control: .leftBrake,
            repetitions: 6,
            note: "selbst herausgefunden"
        )
        SoftUnlockComboStore.save(combo, forSerial: testSerial)

        let loaded = SoftUnlockComboStore.load(forSerial: testSerial)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.control, .leftBrake)
        XCTAssertEqual(loaded?.repetitions, 6)
        XCTAssertEqual(loaded?.displayCode, "Linker Bremshebel 6×")
        XCTAssertFalse(loaded?.entrySteps.isEmpty == true)

        // Andere SN hat keine Kombination.
        XCTAssertNil(SoftUnlockComboStore.load(forSerial: "OTHERSERIAL999"))
    }

    func testSerialNormalizationIsCaseInsensitive() {
        let combo = SoftUnlockCombo(control: .modeButton, repetitions: 4)
        SoftUnlockComboStore.save(combo, forSerial: "abc123sn")
        let loaded = SoftUnlockComboStore.load(forSerial: "  ABC123SN  ")
        XCTAssertEqual(loaded?.control, .modeButton)
        XCTAssertEqual(loaded?.repetitions, 4)
        SoftUnlockComboStore.delete(forSerial: "abc123sn")
    }

    func testDeleteRemovesStoredCombo() {
        SoftUnlockComboStore.save(
            SoftUnlockCombo(control: .rightBrake, repetitions: 3),
            forSerial: testSerial
        )
        XCTAssertNotNil(SoftUnlockComboStore.load(forSerial: testSerial))
        SoftUnlockComboStore.delete(forSerial: testSerial)
        XCTAssertNil(SoftUnlockComboStore.load(forSerial: testSerial))
    }

    func testApplyUpdatesSettingsFromStoredCombo() {
        let settings = SoftUnlockSettings.shared
        let previous = (settings.control, settings.repetitions, settings.isEnabled)
        defer {
            settings.control = previous.0
            settings.repetitions = previous.1
            settings.isEnabled = previous.2
        }
        let combo = SoftUnlockCombo(control: .modeButton, repetitions: 5)
        settings.apply(combo)
        XCTAssertEqual(settings.control, .modeButton)
        XCTAssertEqual(settings.repetitions, 5)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.unlockCodeSummary, "Mode-Taste 5×")
    }

    func testFromSettingsBuildsCombo() {
        let settings = SoftUnlockSettings.shared
        let previous = (settings.control, settings.repetitions, settings.customLabel)
        defer {
            settings.control = previous.0
            settings.repetitions = previous.1
            settings.customLabel = previous.2
        }
        settings.control = .bothBrakes
        settings.repetitions = 8
        let combo = SoftUnlockCombo.fromSettings(settings, note: "manuell")
        XCTAssertEqual(combo.control, .bothBrakes)
        XCTAssertEqual(combo.repetitions, 8)
        XCTAssertEqual(combo.note, "manuell")
        XCTAssertEqual(combo.displayCode, "Beide Bremshebel 8×")
    }

    func testUnlockRescanReportSummaryUsesEnteredCode() {
        let before = IntegrityReading(speedLimitKmh: 20, peakSpeedKmh: 18)
        let after = IntegrityReading(
            speedLimitKmh: 32,
            peakSpeedKmh: 30,
            hiddenTuningDetected: true
        )
        let report = UnlockRescanReport.make(
            unlockCode: "Linker Bremshebel 6×",
            thresholdKmh: 25,
            before: before,
            after: after
        )
        XCTAssertTrue(report.summary.contains("Linker Bremshebel 6×"))
        XCTAssertEqual(report.afterLimitKmh ?? -1, 32, accuracy: 0.1)
        XCTAssertEqual(report.afterPeakKmh ?? -1, 30, accuracy: 0.1)
    }

    func testNoStaatsanwaltWordingInDetectionHint() {
        let hint = SoftUnlockSettings.shared.detectionHint.lowercased()
        XCTAssertFalse(hint.contains("staatsanwalt"))
        XCTAssertFalse(hint.contains("staatsanwaltschaft"))
        XCTAssertTrue(hint.contains("geheimkombination") || hint.contains("kombination"))
        XCTAssertTrue(hint.contains("seriennummer") || hint.contains("gespeichert"))
    }

    func testNoBuiltInCatalogAPI() {
        // SoftUnlockCatalog wurde entfernt — Kombinationen kommen nur aus dem Store.
        XCTAssertTrue(SoftUnlockComboStore.allStored() is [String: SoftUnlockCombo])
    }
}
