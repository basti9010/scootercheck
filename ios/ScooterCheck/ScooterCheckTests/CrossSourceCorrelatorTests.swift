import XCTest
@testable import ScooterCheck

final class CrossSourceCorrelatorTests: XCTestCase {

    // MARK: - Firmware version

    func testMatchingFirmwareStringsAreConfirmed() {
        let snapshot = CrossSourceSnapshot(
            bleDevice: nil,
            firmwareVersions: CorrelationFirmwareVersions(fwVcu: "1.5.8"),
            deviceTraits: nil,
            zipMeta: CorrelationZipMeta(
                fileName: "DRV_1.5.8_G3.zip",
                displayName: "Max G3 DRV 1.5.8",
                models: ["G3"],
                compatibleBoards: [],
                computedMd5: nil,
                declaredMd5: nil,
                md5Matches: nil,
                firmSizeBytes: nil,
                findings: []
            ),
            forensicStub: nil
        )
        let result = CrossSourceCorrelator.assess(snapshot)
        let fw = result.items.first { $0.kind == .firmwareVersion }
        XCTAssertEqual(fw?.epistemics, .confirmed)
        XCTAssertEqual(fw?.confidence, .high)
        XCTAssertTrue(result.confirmedItems.contains { $0.kind == .firmwareVersion })
    }

    func testFirmwareMismatchIsHypothesisConflict() {
        let snapshot = CrossSourceSnapshot(
            bleDevice: nil,
            firmwareVersions: CorrelationFirmwareVersions(fwMcu: "1.5.8", fwBle: "1.2.0"),
            deviceTraits: nil,
            zipMeta: CorrelationZipMeta(
                fileName: "custom.zip",
                displayName: "Max G30 CFW 2.0.0-dev",
                models: ["max"],
                compatibleBoards: [],
                computedMd5: "abcd",
                declaredMd5: nil,
                md5Matches: nil,
                firmSizeBytes: 100,
                findings: []
            ),
            forensicStub: nil
        )
        let result = CrossSourceCorrelator.assess(snapshot)
        let fw = result.items.first { $0.kind == .firmwareVersion }
        XCTAssertEqual(fw?.epistemics, .hypothesis)
        XCTAssertNotEqual(fw?.epistemics, .confirmed)
        XCTAssertTrue(fw?.id.contains("conflict") == true || fw?.title.lowercased().contains("konflikt") == true)
    }

    func testDigitOnlyFuzzyMatchIsHypothesisNotConfirmed() {
        let snapshot = CrossSourceSnapshot(
            firmwareVersions: CorrelationFirmwareVersions(fwVcu: "1.5.8"),
            zipMeta: CorrelationZipMeta(
                fileName: "build158.zip",
                displayName: "build158 release",
                models: [],
                compatibleBoards: [],
                computedMd5: nil,
                declaredMd5: nil,
                md5Matches: nil,
                firmSizeBytes: nil,
                findings: []
            )
        )
        let fw = CrossSourceCorrelator.assess(snapshot).items.first { $0.kind == .firmwareVersion }
        XCTAssertEqual(fw?.epistemics, .hypothesis)
        XCTAssertEqual(fw?.id, "fwVersion-fuzzy")
    }

    // MARK: - Missing sources

    func testMissingDumpIsIncompleteNotConfirmed() {
        let snapshot = CrossSourceSnapshot(
            zipMeta: CorrelationZipMeta(
                fileName: "only.zip",
                displayName: "G3 1.5.8",
                models: ["G3"],
                compatibleBoards: [],
                computedMd5: "deadbeef",
                declaredMd5: nil,
                md5Matches: nil,
                firmSizeBytes: 12,
                findings: []
            )
        )
        let result = CrossSourceCorrelator.assess(snapshot)
        let fw = result.items.first { $0.kind == .firmwareVersion }
        XCTAssertEqual(fw?.epistemics, .incomplete)
        XCTAssertFalse(result.confirmedItems.contains { $0.kind == .firmwareVersion })
        XCTAssertTrue(result.caveats.contains(where: { $0.contains("ZIP") && $0.contains("installierte") }))
    }

    func testMissingZipIsIncompleteNotConfirmed() {
        let snapshot = CrossSourceSnapshot(
            firmwareVersions: CorrelationFirmwareVersions(fwVcu: "1.5.8", fwMcu: "1.4.0")
        )
        let result = CrossSourceCorrelator.assess(snapshot)
        let fw = result.items.first { $0.kind == .firmwareVersion }
        XCTAssertEqual(fw?.epistemics, .incomplete)
        XCTAssertTrue(result.confirmedItems.isEmpty)
    }

    func testEmptySnapshotAllIncompleteWithCaveat() {
        let result = CrossSourceCorrelator.assess(CrossSourceSnapshot())
        XCTAssertTrue(result.confirmedItems.isEmpty)
        XCTAssertTrue(result.items.allSatisfy { $0.epistemics == .incomplete })
        XCTAssertTrue(result.caveats.contains(CrossSourceSnapshot.zipNotInstalledCaveat))
    }

    // MARK: - Model family

    func testModelFamilyConfirmedWithBleMediumEscoter() {
        let snapshot = CrossSourceSnapshot(
            bleDevice: CorrelationBLEDeviceInfo(
                peripheralId: UUID(),
                categoryRaw: "eScooter",
                confidenceRaw: "medium",
                model: "Max G3",
                manufacturer: "Ninebot",
                listTitle: "MIScooter"
            ),
            firmwareVersions: nil,
            deviceTraits: CorrelationDeviceIdTraits(
                profileLabel: "Max G3 / MAX3 D",
                modelLabel: "G3",
                serialDisplay: nil,
                blePeripheralId: nil
            ),
            zipMeta: CorrelationZipMeta(
                fileName: "g3.zip",
                displayName: "G3 Stock",
                models: ["G3"],
                compatibleBoards: ["max_g3_drv"],
                computedMd5: nil,
                declaredMd5: nil,
                md5Matches: nil,
                firmSizeBytes: nil,
                findings: []
            ),
            forensicStub: nil
        )
        let item = CrossSourceCorrelator.assess(snapshot).items.first { $0.kind == .modelFamily }
        XCTAssertEqual(item?.epistemics, .confirmed)
    }

    func testModelFamilyZipOnlyIsHypothesis() {
        let snapshot = CrossSourceSnapshot(
            zipMeta: CorrelationZipMeta(
                fileName: "g3.zip",
                displayName: "G3",
                models: ["G3"],
                compatibleBoards: [],
                computedMd5: nil,
                declaredMd5: nil,
                md5Matches: nil,
                firmSizeBytes: nil,
                findings: []
            )
        )
        let item = CrossSourceCorrelator.assess(snapshot).items.first { $0.kind == .modelFamily }
        XCTAssertEqual(item?.epistemics, .hypothesis)
        XCTAssertNotEqual(item?.epistemics, .confirmed)
    }

    // MARK: - Digest

    func testMd5AloneIsHypothesisNeverInstalledClaim() {
        let snapshot = CrossSourceSnapshot(
            zipMeta: CorrelationZipMeta(
                fileName: "x.zip",
                displayName: nil,
                models: [],
                compatibleBoards: [],
                computedMd5: "aabbccddeeff00112233445566778899",
                declaredMd5: "aabbccddeeff00112233445566778899",
                md5Matches: true,
                firmSizeBytes: 4096,
                findings: []
            )
        )
        let result = CrossSourceCorrelator.assess(snapshot)
        let digest = result.items.first { $0.kind == .imageDigestHint }
        XCTAssertEqual(digest?.epistemics, .hypothesis)
        XCTAssertTrue(digest?.detail.lowercased().contains("live") == true
                      || digest?.detail.lowercased().contains("kein") == true)
        XCTAssertTrue(result.caveats.contains(where: {
            $0.lowercased().contains("installation") || $0.contains("ZIP")
        }))
        XCTAssertFalse(digest?.detail.lowercased().contains("installiert und bestätigt") == true)
    }

    // MARK: - Softening

    func testSofteningDemotesGenericPowerButtonNeedle() {
        let finding = CorrelationZipFindingInput(
            id: "1",
            kindRaw: "unlockGesture",
            title: "Power",
            detail: "Treffer „power button“ in Binary",
            confidence: .high,
            source: "binary",
            needle: "power button"
        )
        let soft = ZipFindingSoftening.softenOne(finding)
        XCTAssertEqual(soft.confidence, .low)
        XCTAssertEqual(soft.epistemics, .hypothesis)
        XCTAssertNotNil(soft.annotation)
    }

    func testSofteningKeepsCustomSignatureConfidenceButHypothesis() {
        let finding = CorrelationZipFindingInput(
            id: "2",
            kindRaw: "customFirmware",
            title: "ScooterHacking",
            detail: "Signatur ScooterHacking",
            confidence: .high,
            source: "binary",
            needle: "ScooterHacking"
        )
        let soft = ZipFindingSoftening.softenOne(finding)
        XCTAssertEqual(soft.confidence, .high)
        XCTAssertEqual(soft.epistemics, .hypothesis)
        XCTAssertTrue(soft.annotation?.contains("unbestätigt") == true)
    }

    // MARK: - Labels / isolation smoke

    func testEpistemicsGermanLabels() {
        XCTAssertEqual(CorrelationEpistemics.confirmed.label, "Bestätigt")
        XCTAssertEqual(CorrelationEpistemics.hypothesis.label, "Hypothese")
        XCTAssertEqual(CorrelationEpistemics.incomplete.label, "Unvollständig")
    }

    func testAssessmentNeverImpliesEvidenceRewrite() {
        // Smoke: correlator returns attributionHints side-channel only; no verdict field exists.
        let result = CrossSourceCorrelator.assess(
            CrossSourceSnapshot(
                firmwareVersions: CorrelationFirmwareVersions(fwVcu: "1.0.0"),
                zipMeta: CorrelationZipMeta(
                    fileName: "a.zip",
                    displayName: "1.0.0",
                    models: [],
                    compatibleBoards: [],
                    computedMd5: nil,
                    declaredMd5: nil,
                    md5Matches: nil,
                    firmSizeBytes: nil,
                    findings: []
                )
            )
        )
        XCTAssertTrue(result.confirmedItems.contains { $0.kind == .firmwareVersion })
        // API surface: no verdict/score on assessment
        XCTAssertNil(Mirror(reflecting: result).children.first { $0.label == "verdict" })
        XCTAssertNil(Mirror(reflecting: result).children.first { $0.label == "score" })
    }
}
