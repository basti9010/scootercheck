import XCTest
@testable import ScooterCheck

final class FirmwareReadoutMatchCorrelatorTests: XCTestCase {

    func testInconclusiveWithoutLiveReadout() {
        let report = sampleReport(fileName: "ZT3_VCU_48KMH.zip", models: ["zt3"], type: "VCU")
        let a = FirmwareReadoutMatchCorrelator.assess(report: report, vehicleContext: nil)
        XCTAssertEqual(a.verdict, .inconclusive)
        XCTAssertTrue(a.checks.isEmpty)
    }

    func testLikelyMatchWhenModelControllerVersionAndSpeedAlign() {
        var deep = emptyDeep()
        deep.speedLimits = [
            FirmwareSpeedLimitFinding(
                id: "l20",
                kmh: 20,
                packedU16: nil,
                role: .legalCap,
                evidence: "test",
                source: .localDeterministic,
                confidence: .high
            ),
            FirmwareSpeedLimitFinding(
                id: "l48",
                kmh: 48,
                packedU16: nil,
                role: .openCap,
                evidence: "test",
                source: .localDeterministic,
                confidence: .high
            )
        ]
        deep.maxSpeedKmhInCode = 48

        let report = sampleReport(
            fileName: "ZT3_VCU_48KMH.zip",
            models: ["zt3"],
            type: "VCU",
            displayName: "ZT3 VCU 1.2.1",
            deep: deep
        )
        let ctx = FirmwareVehicleContext(
            manufacturer: "Ninebot",
            modelLabel: "ZT3 Pro",
            profileId: "zt3",
            serial: "ABC",
            fwVcu: "1.2.1",
            fwMcu: nil,
            fwBle: nil,
            fwEsc: nil,
            speedLimitKmh: 20,
            speedMaxKmh: 20,
            peakSpeedKmh: 19,
            protocolNumber: nil,
            fromLiveReadout: true
        )

        let a = FirmwareReadoutMatchCorrelator.assess(report: report, vehicleContext: ctx)
        XCTAssertEqual(a.verdict, .likelyMatch)
        XCTAssertEqual(a.checks.first { $0.id == "model" }?.status, .match)
        XCTAssertEqual(a.checks.first { $0.id == "controller" }?.status, .match)
        XCTAssertEqual(a.checks.first { $0.id == "version" }?.status, .match)
        // Live-Limit 20 nahe Code-Stufe 20
        XCTAssertEqual(a.checks.first { $0.id == "speed" }?.status, .match)
        XCTAssertFalse(a.caveats.isEmpty)
    }

    func testSpeedMismatchWhenFilenameClaimsMuchHigherThanLiveLimit() {
        let report = sampleReport(
            fileName: "ZT3_VCU_48KMH.zip",
            models: ["zt3"],
            type: "VCU",
            deep: {
                var d = emptyDeep()
                d.maxSpeedKmhInCode = 48
                d.speedLimits = [
                    FirmwareSpeedLimitFinding(
                        id: "l48",
                        kmh: 48,
                        packedU16: nil,
                        role: .openCap,
                        evidence: "test",
                        source: .localDeterministic,
                        confidence: .medium
                    )
                ]
                return d
            }()
        )
        // Live limit far below claim, and claim not near a code stage used as live limit match
        // speedCheck: lim+5 < claim and fileMax >= claim → mismatch
        let ctx = FirmwareVehicleContext(
            manufacturer: nil,
            modelLabel: "ZT3",
            profileId: "zt3",
            serial: nil,
            fwVcu: "9.9.9",
            fwMcu: nil,
            fwBle: nil,
            fwEsc: nil,
            speedLimitKmh: 22,
            speedMaxKmh: 22,
            peakSpeedKmh: nil,
            protocolNumber: nil,
            fromLiveReadout: true
        )
        let a = FirmwareReadoutMatchCorrelator.assess(report: report, vehicleContext: ctx)
        XCTAssertEqual(a.checks.first { $0.id == "speed" }?.status, .mismatch)
        XCTAssertTrue([.partial, .mismatch].contains(a.verdict))
    }

    func testModelMismatch() {
        let report = sampleReport(fileName: "F2_VCU.bin", models: ["f2"], type: "VCU")
        let ctx = FirmwareVehicleContext(
            manufacturer: nil,
            modelLabel: "G3",
            profileId: "g3",
            serial: nil,
            fwVcu: "1.0.0",
            fwMcu: nil,
            fwBle: nil,
            fwEsc: nil,
            speedLimitKmh: 20,
            speedMaxKmh: nil,
            peakSpeedKmh: nil,
            protocolNumber: nil,
            fromLiveReadout: true
        )
        let a = FirmwareReadoutMatchCorrelator.assess(report: report, vehicleContext: ctx)
        XCTAssertEqual(a.checks.first { $0.id == "model" }?.status, .mismatch)
    }

    // MARK: - Helpers

    private func emptyDeep() -> FirmwareDeepAnalysisResult {
        FirmwareDeepAnalysisResult(
            schemaVersion: FirmwareDeepAnalysisResult.currentSchemaVersion,
            producedAt: Date(),
            sources: [.localDeterministic],
            subjectSHA256: "0",
            packageDisplayName: nil,
            models: [],
            controllerType: "VCU",
            speedLimits: [],
            maxSpeedKmhInCode: nil,
            legalCapKmhInCode: nil,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: [],
            caveats: FirmwareDeepAnalysisResult.standardCaveats,
            quality: FirmwareDeepAnalysisQuality(
                hasDeterministicBasis: true,
                llmSchemaValidated: false,
                summary: "test"
            )
        )
    }

    private func sampleReport(
        fileName: String,
        models: [String],
        type: String,
        displayName: String? = nil,
        deep: FirmwareDeepAnalysisResult? = nil
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
                displayName: displayName ?? fileName,
                models: models,
                type: type,
                compatible: models.map { "\($0)_VCU" },
                declaredMd5: nil,
                declaredEncrypted: true,
                rawInfoJSON: displayName.map { "{\"name\":\"\($0)\"}" }
            ),
            entries: [],
            primaryFirmwarePath: "FIRM.bin.enc",
            crypto: FirmwareCryptoAssessment(
                status: .confirmedByMetadata,
                detectedFormat: "TEA/XTEA",
                decryptionAvailable: false,
                decryptionNote: "test",
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
            evidence: [],
            comparison: nil,
            verdict: .yellow,
            verdictRationale: "test",
            limits: [],
            vehicleContext: nil,
            vehicleLinkNotes: [],
            summary: "test",
            deepAnalysis: deep
        )
    }
}
