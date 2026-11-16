import XCTest
@testable import ScooterCheck

final class CfwHardwareForensicsTests: XCTestCase {

    func testDecodeCfwShFromMcuRand() {
        var reading = IntegrityReading()
        let spec = DiagnosticMap.Spec(
            id: "vcu_g3_mcu_rand",
            board: .vcuG3,
            register: Nb.G3Register.mcuRand,
            readLen: 6,
            category: .status
        )
        // "cfw.sh" = 63 66 77 2E 73 68
        DiagnosticMap.apply(
            spec: spec,
            data: Data([0x63, 0x66, 0x77, 0x2E, 0x73, 0x68]),
            into: &reading
        )
        XCTAssertEqual(reading.mcuRandMarker, "cfw.sh")
        XCTAssertEqual(reading.fwAppCustom, true)
        XCTAssertTrue(CfwHardwareForensics.isSuspiciousMarker("cfw.sh"))
    }

    func testDecodeCjsSgkFromVcuRand() {
        var reading = IntegrityReading()
        let spec = DiagnosticMap.Spec(
            id: "vcu_g3_rand",
            board: .vcuG3,
            register: Nb.G3Register.rand,
            readLen: 6,
            category: .status
        )
        // "cjsSgk" = 63 6A 73 53 67 6B
        DiagnosticMap.apply(
            spec: spec,
            data: Data([0x63, 0x6A, 0x73, 0x53, 0x67, 0x6B]),
            into: &reading
        )
        XCTAssertEqual(reading.vcuRandMarker, "cjsSgk")
        XCTAssertEqual(reading.fwAppCustom, true)
    }

    func testDecodeDeviceUIDs() {
        var reading = IntegrityReading()
        let vcu = DiagnosticMap.Spec(
            id: "vcu_g3_cpuid",
            board: .vcuG3,
            register: Nb.G3Register.cpuId,
            readLen: 12,
            category: .status
        )
        DiagnosticMap.apply(
            spec: vcu,
            data: Data([0xE8, 0x66, 0x03, 0x59, 0xC0, 0x00, 0x1D, 0xA6, 0x27, 0x04, 0x05, 0xDC]),
            into: &reading
        )
        XCTAssertEqual(reading.vcuDeviceUid, "E866 0359 C000 1DA6 2704 05DC")
    }

    func testEvidenceFlagsCfwMarkerOnF3() {
        let reading = IntegrityReading(
            serialDisplay: "1EFHE2515C0440",
            mcuRandMarker: "cfw.sh",
            vcuRandMarker: "cjsSgk",
            fwAppCustom: true
        )
        let evidence = EvidenceEngine.evaluate(reading: reading, profile: .ninebotF3D)
        XCTAssertTrue(evidence.results.contains { $0.fact.markerID == "fw.rand.cfw" })
        XCTAssertTrue(evidence.results.contains { $0.fact.markerID == "fw.custom" })

        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .ninebotF3D)
        let randFact = result.facts.first { $0.id == "fw.rand.marker" }
        XCTAssertNotNil(randFact)
        XCTAssertEqual(randFact?.status, .erheblichAbweichend)
        XCTAssertTrue((randFact?.auslesewert ?? "").contains("cfw.sh"))
        XCTAssertTrue(result.facts.contains { $0.id == "hw.board.types" })
    }

    func testBackfillFromRawRegisters() {
        var reading = IntegrityReading(
            rawRegisters: [
                RawRegister(
                    address: "22-C7",
                    index: 0xC7,
                    name: "vcu_g3_mcu_rand",
                    valueHex: "6366772E7368",
                    valueDecoded: "cfw.sh"
                )
            ]
        )
        IntegrityAnalyzer.backfillCfwMarkersFromRawRegisters(&reading)
        XCTAssertEqual(reading.mcuRandMarker, "cfw.sh")
        XCTAssertEqual(reading.fwAppCustom, true)
    }

    func testStockBoardTypesForF3() {
        let boards = CfwHardwareForensics.inferredBoardTypes(for: .ninebotF3D)
        XCTAssertEqual(boards.first { $0.label == "VCU" }?.value, "f3_VCU_AT32")
        XCTAssertEqual(boards.first { $0.label == "MCU" }?.value, "x3_MCU_AT32")
    }
}
