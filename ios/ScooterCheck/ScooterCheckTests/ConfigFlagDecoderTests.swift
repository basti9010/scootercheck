import XCTest
@testable import ScooterCheck

final class ConfigFlagDecoderTests: XCTestCase {

    func testFunBoolAutoLockBit() {
        let decoded = ConfigFlagDecoder.decodeFunBool(hex: "0x0004")
        XCTAssertEqual(decoded?.raw, 0x0004)
        XCTAssertEqual(decoded?.activeLabels, ["Auto-Key-Lock / Walk-away-Lock"])
        XCTAssertEqual(decoded?.unknownMask, 0)
        XCTAssertTrue(decoded?.displayValue.contains("Auto-Key-Lock") == true)
    }

    func testFunBoolMultipleAndRest() {
        // 0x0004 known + 0x0010 unknown
        let decoded = ConfigFlagDecoder.decodeFunBool(hex: "0x0014")
        XCTAssertEqual(decoded?.activeLabels, ["Auto-Key-Lock / Walk-away-Lock"])
        XCTAssertEqual(decoded?.unknownMask, 0x0010)
        XCTAssertTrue(decoded?.displayValue.contains("Rest 0x0010") == true)
    }

    func testBoolUnlockPasscode() {
        let decoded = ConfigFlagDecoder.decodeBool(hex: "0x0040")
        XCTAssertEqual(decoded?.activeLabels, ["Entsperr-PIN aktiv"])
    }

    func testParseHexAcceptsWithoutPrefix() {
        XCTAssertEqual(ConfigFlagDecoder.parseHex("00AA"), 0x00AA)
        XCTAssertEqual(ConfigFlagDecoder.parseHex("0xaa"), 0x00AA)
    }

    func testAnalyzerShowsDecodedFunAndCustomKey() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBF2531C0230",
            configFunHex: "0x0004",
            configCustomKeyHex: "0x1234",
            configEncFlagHex: "0x0000"
        )
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3D)
        let fun = result.facts.first { $0.id == "config.fun" }
        XCTAssertTrue(fun?.auslesewert.contains("Auto-Key-Lock") == true)
        XCTAssertEqual(result.facts.first { $0.id == "config.custom_key" }?.auslesewert, "0x1234")
        XCTAssertEqual(result.facts.first { $0.id == "config.custom_key" }?.status, .regelkonform)
    }

    func testDiagnosticMapAppliesCustomKey() {
        var reading = IntegrityReading()
        let spec = DiagnosticMap.Spec(
            id: "vcu_g3_custom_key",
            board: .vcuG3,
            register: Nb.G3Register.customKey,
            readLen: 2,
            category: .status
        )
        DiagnosticMap.apply(spec: spec, data: Data([0x34, 0x12]), into: &reading)
        XCTAssertEqual(reading.configCustomKeyHex, "0x1234")
    }
}
