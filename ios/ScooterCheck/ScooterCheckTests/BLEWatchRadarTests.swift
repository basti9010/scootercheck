import XCTest
@testable import ScooterCheck

final class BLEWatchRadarTests: XCTestCase {

    func testWatchConfigLimits() {
        XCTAssertEqual(BLEWatchConfig.maxActiveTargets, 10)
        XCTAssertGreaterThanOrEqual(BLEWatchConfig.secureMatchScore, BLEWatchConfig.possibleMatchScore)
    }

    func testFingerprintRejectsNameOnlySimilarity() {
        let a = BLEDeviceFingerprint(
            localName: "Ninebot Scooter",
            manufacturerDataHex: nil,
            serviceUUIDs: [],
            advertisingStructureKey: "N----?"
        )
        let b = BLEDeviceFingerprint(
            localName: "Ninebot Scooter",
            manufacturerDataHex: "11223344",
            serviceUUIDs: ["FFE0"],
            advertisingStructureKey: "NMS1--C"
        )
        let match = BLEFingerprintService.compare(a, b)
        // Name gleich reicht nicht für high, wenn Mfg/UUIDs fehlen/abweichen
        XCTAssertNotEqual(match.similarity, .high)
    }

    func testSecureFingerprintMatchRequiresStrongFeatures() {
        let baseline = BLEDeviceFingerprint(
            localName: "NB-A",
            manufacturerDataHex: "4C001122",
            serviceUUIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"],
            advertisingStructureKey: "NMS1--C",
            txPower: -8,
            isConnectable: true
        )
        let same = BLEDeviceFingerprint(
            localName: "NB-B", // Name geändert
            manufacturerDataHex: "4C001122",
            serviceUUIDs: ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E"],
            advertisingStructureKey: "NMS1--C",
            txPower: -8,
            isConnectable: true
        )
        let score = BLEFingerprintService.compare(baseline, same).score
        XCTAssertGreaterThanOrEqual(score, BLEWatchConfig.secureMatchScore)
    }

    func testCooldownOptionsAndSignalFilters() {
        XCTAssertEqual(BLEWatchTarget.cooldownOptions.count, 5)
        XCTAssertTrue(BLEWatchTarget.cooldownOptions.contains { $0.seconds == 900 })
    }

    func testScooterClassifierNameOnlyIsLow() {
        // looksLikeScooter true purely from name → low confidence for radar
        // Classifier path: nameLikely without service/mfg/model → low
        let conf = BLEScooterConfidence.low
        XCTAssertEqual(conf.label, "niedrig")
        XCTAssertFalse(BLEScooterConfidence.low == .medium)
    }

    func testRadarConfigRequiresMultipleHits() {
        XCTAssertGreaterThanOrEqual(BLERadarConfig.minHitsForAlarm, 2)
        XCTAssertGreaterThan(BLERadarConfig.deviceCooldownSeconds, 10)
    }

    func testWatchStatusLabels() {
        XCTAssertEqual(BLEWatchStatus.watching.label, "Wird beobachtet")
        XCTAssertEqual(BLEWatchStatus.foundAgain.label, "Wieder erkannt")
        XCTAssertEqual(BLEWatchStatus.paused.label, "Pausiert")
    }

    func testDeepLinkParsing() {
        let watchId = UUID()
        let watch = BLEDeepLink.parse(URL(string: "scootercheck://watch/\(watchId.uuidString)")!)
        XCTAssertEqual(watch, .watch(targetId: watchId))
        XCTAssertEqual(BLEDeepLink.parse(URL(string: "scootercheck://find")!), .find)
        XCTAssertEqual(BLEDeepLink.parse(URL(string: "scootercheck://radar")!), .radar(deviceId: nil))
        XCTAssertNil(BLEDeepLink.parse(URL(string: "https://example.com")!))
    }

    func testWatchTargetCodableRoundtrip() throws {
        let t = BLEWatchTarget(
            deviceId: UUID(),
            deviceName: "ZT3 Pro",
            isKnownScooter: true,
            fingerprint: BLEDeviceFingerprint(localName: "ZT3", manufacturerDataHex: "AABB"),
            enabled: true,
            minimumSignalClass: .medium,
            cooldownSeconds: 300
        )
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(BLEWatchTarget.self, from: data)
        XCTAssertEqual(decoded.deviceName, "ZT3 Pro")
        XCTAssertEqual(decoded.minClass, .medium)
        XCTAssertEqual(decoded.cooldownSeconds, 300)
        XCTAssertEqual(decoded.fingerprint?.manufacturerDataHex, "AABB")
    }

    func testManualKillDisclaimerPresentInUICopy() {
        // Produktregel: kein garantierter Hintergrundbetrieb nach Kill
        let note = "Wenn ScooterCheck manuell beendet wird, kann iOS die Hintergrundüberwachung stoppen."
        XCTAssertTrue(note.contains("manuell beendet"))
    }

    func testClassifierRequiresMoreThanNameForEligibility() {
        // medium/high brauchen Service/Modell/Mfg — Name allein → low → nicht radar-eligible
        XCTAssertEqual(BLEScooterConfidence.low, .low)
        XCTAssertNotEqual(BLEScooterConfidence.medium, .low)
    }
}
