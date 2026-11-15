import XCTest
@testable import ScooterCheck

final class DualSourcePanicCorrelatorTests: XCTestCase {

    func testPanicResetWhenPhoneSuspiciousAndLiveStock() {
        let forensic = sampleForensic(
            fileName: "G3 VCU panicsystem-1.zip",
            verdict: .yellow,
            encrypted: true
        )
        var reading = IntegrityReading()
        reading.serialDisplay = "1EFCE2515C0440"
        reading.speedLimitKmh = 20
        reading.speedMaxKmh = 20
        reading.fwVcu = "1.6.1"

        let a = DualSourcePanicCorrelator.assess(
            forensic: forensic,
            reading: reading,
            profile: .ninebotF3D
        )
        XCTAssertEqual(a.pattern, .panicResetSuspected)
        XCTAssertTrue(a.phoneSuspicious)
        XCTAssertTrue(a.liveLooksStock)
        XCTAssertFalse(a.liveLooksTuned)
        XCTAssertTrue(a.nextSteps.contains { $0.localizedCaseInsensitiveContains("Vergleichstest") })
    }

    func testActiveTuningWhenLiveElevated() {
        var reading = IntegrityReading()
        reading.speedLimitKmh = 35
        reading.speedMaxKmh = 35
        reading.fwVcu = "1.6.1"

        let a = DualSourcePanicCorrelator.assess(
            forensic: nil,
            reading: reading,
            profile: .ninebotF3D
        )
        XCTAssertEqual(a.pattern, .liveOnly)
        XCTAssertTrue(a.liveLooksTuned)
    }

    func testBothSuspicious() {
        let forensic = sampleForensic(fileName: "cfw.zip", verdict: .red, encrypted: false)
        var reading = IntegrityReading()
        reading.speedLimitKmh = 35
        reading.speedMaxKmh = 35

        let a = DualSourcePanicCorrelator.assess(
            forensic: forensic,
            reading: reading,
            profile: .ninebotF3D
        )
        XCTAssertEqual(a.pattern, .bothSuspicious)
    }

    func testStoreRoundTrip() throws {
        DualSourceCaseStore.clear()
        let forensic = sampleForensic(fileName: "x.zip", verdict: .gray, encrypted: true)
        DualSourceCaseStore.saveForensic(forensic)
        let loaded = try XCTUnwrap(DualSourceCaseStore.loadForensic())
        XCTAssertEqual(loaded.originalFileName, "x.zip")
        DualSourceCaseStore.clear()
        XCTAssertNil(DualSourceCaseStore.loadForensic())
    }

    private func sampleForensic(
        fileName: String,
        verdict: FirmwareForensicVerdict,
        encrypted: Bool
    ) -> FirmwareForensicReport {
        let digest = FirmwareFileDigest(md5: "0", sha256: "0", byteCount: 1, shannonEntropy: 7.9)
        return FirmwareForensicReport(
            id: UUID().uuidString,
            analyzedAt: Date(),
            originalFileName: fileName,
            containerKind: .zipV3,
            archiveByteCount: 1,
            archiveDigest: digest,
            meta: FirmwarePackageMeta(
                schemaVersion: 2,
                displayName: "test",
                models: ["g3"],
                type: "VCU",
                compatible: ["g3_VCU"],
                declaredMd5: nil,
                declaredEncrypted: encrypted,
                rawInfoJSON: nil
            ),
            entries: [],
            primaryFirmwarePath: "FIRM.bin.enc",
            crypto: FirmwareCryptoAssessment(
                status: encrypted ? .confirmedByMetadata : .plaintext,
                detectedFormat: encrypted ? "TEA/XTEA" : "bin",
                decryptionAvailable: false,
                decryptionNote: "offline unavailable",
                evidence: []
            ),
            binary: FirmwareBinaryAnalysis(
                performed: false,
                unavailableReason: "encrypted",
                architecture: .unknown,
                vectorTableLikely: false,
                resetHandlerHint: nil,
                stringsSample: [],
                codeDataNotes: []
            ),
            evidence: filenamePanic.contains(where: { fileName.lowercased().contains($0) })
                ? [
                    FirmwareEvidenceItem(
                        id: "fn",
                        category: .filenameHint,
                        title: "Dateiname",
                        detail: fileName,
                        evidence: fileName,
                        method: "filename",
                        verifiability: .unverified,
                        confirmed: false
                    )
                ]
                : [],
            comparison: nil,
            verdict: verdict,
            verdictRationale: "test",
            limits: ["no flash"],
            vehicleContext: nil,
            vehicleLinkNotes: [],
            summary: "test",
            deepAnalysis: nil
        )
    }

    private var filenamePanic: [String] { ["panic", "cfw"] }
}
