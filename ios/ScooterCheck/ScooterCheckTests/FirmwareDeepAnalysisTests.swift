import XCTest
@testable import ScooterCheck

final class FirmwareDeepAnalysisTests: XCTestCase {

    func testKnownCatalogMatchesG3PanicbuttonHash() {
        let entry = FirmwareKnownCFWCatalog.match(
            md5: "0a567b134861a5f9f7e4683e63d8f4a8",
            sha256: "929a01874b64c1e7dd075648d45d0c12305bff9bb3cc236d58a3fb6e1dba2180"
        )
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.displayName, "Panicbutton (Starke-Tech.de)")

        let deep = FirmwareKnownCFWCatalog.deepAnalysis(
            for: try XCTUnwrap(entry),
            subjectSHA256: "929a01874b64c1e7dd075648d45d0c12305bff9bb3cc236d58a3fb6e1dba2180"
        )
        XCTAssertTrue(deep.quality.hasDeterministicBasis)
        XCTAssertEqual(deep.maxSpeedKmhInCode, 99)
        XCTAssertEqual(deep.legalCapKmhInCode, 20)
        XCTAssertFalse(deep.comboSummaries.isEmpty)
        XCTAssertTrue(deep.inputHints.contains { $0.kind == .throttle })
        XCTAssertTrue(deep.inputHints.contains { $0.kind == .brake })
    }

    func testDecompileScanFindsPackedSpeeds() {
        let snippet = """
        void FUN_test(void) {
          *(undefined2 *)(iVar6 + 0x8c) = 0x1400;
          uVar5 = 0x1600;
          uVar5 = 0x1900;
          uVar5 = 0x6300;
          *(undefined2 *)(iVar6 + 0x8c) = 0x2000;
        }
        """
        let meta = FirmwarePackageMeta(
            schemaVersion: 1,
            displayName: "test",
            models: ["g3"],
            type: "VCU",
            compatible: [],
            declaredMd5: nil,
            declaredEncrypted: false,
            rawInfoJSON: nil
        )
        let deep = FirmwareSpeedSignatureExtractor.extract(
            fromBinary: nil,
            decompiledText: snippet,
            subjectSHA256: "abc",
            meta: meta
        )
        XCTAssertTrue(deep.quality.hasDeterministicBasis)
        XCTAssertEqual(deep.maxSpeedKmhInCode, 99)
        XCTAssertEqual(deep.legalCapKmhInCode, 20)
        let kmhs = Set(deep.speedLimits.map(\.kmh))
        XCTAssertTrue(kmhs.contains(22))
        XCTAssertTrue(kmhs.contains(32))
    }

    func testBinaryScanFindsLEPackedU16() {
        // little-endian 0x1600 → bytes 00 16; 0x6300 → 00 63
        let data = Data([0x00, 0x16, 0xFF, 0x00, 0x63])
        let meta = FirmwarePackageMeta(
            schemaVersion: 1,
            displayName: nil,
            models: [],
            type: nil,
            compatible: [],
            declaredMd5: nil,
            declaredEncrypted: nil,
            rawInfoJSON: nil
        )
        let deep = FirmwareSpeedSignatureExtractor.extract(
            fromBinary: data,
            decompiledText: nil,
            subjectSHA256: "bin",
            meta: meta
        )
        XCTAssertEqual(deep.maxSpeedKmhInCode, 99)
        XCTAssertTrue(deep.speedLimits.contains { $0.kmh == 22 })
    }

    func testMergerPrefersCatalogAndValidateRejectsEmptyLLM() {
        let entry = FirmwareKnownCFWCatalog.g3PanicbuttonStarkeTech
        let cat = FirmwareKnownCFWCatalog.deepAnalysis(for: entry, subjectSHA256: "x")
        let emptyLLM = FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(),
            sources: [.serverLLM],
            subjectSHA256: "x",
            packageDisplayName: nil,
            models: [],
            controllerType: nil,
            speedLimits: [],
            maxSpeedKmhInCode: nil,
            legalCapKmhInCode: nil,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: [],
            caveats: [],
            quality: .init(hasDeterministicBasis: false, llmSchemaValidated: false, summary: "")
        )
        XCTAssertNil(FirmwareDeepAnalysisMerger.validateServerResult(emptyLLM))

        let merged = FirmwareDeepAnalysisMerger.merge([cat])
        XCTAssertEqual(merged?.maxSpeedKmhInCode, 99)
    }

    func testOrchestratorAttachesCatalogDeepAnalysisForMatchingENC() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("G3_VCU_Panicbutton_2026.zip")
        let data = try Data(contentsOf: fixtures)
        let report = FirmwareForensicOrchestrator.analyze(
            fileName: "G3_VCU_Panicbutton_2026.zip",
            data: data
        )
        let deep = try XCTUnwrap(report.deepAnalysis)
        XCTAssertTrue(deep.quality.hasDeterministicBasis)
        XCTAssertEqual(deep.maxSpeedKmhInCode, 99)
        XCTAssertEqual(deep.legalCapKmhInCode, 20)
        XCTAssertTrue(deep.sources.contains(.knownCatalog))
        XCTAssertFalse(deep.comboSummaries.isEmpty)
    }
}
