import XCTest
@testable import ScooterCheck

final class VcuFirmwareVersionTests: XCTestCase {
    /// Rohbytes `61 01` = LE u16 0x0161 → major.minor.patch = 1.6.1
    /// Früherer Bug: 4-Byte-Read `61 01 57 01` → fälschlich `97.1.87.1`
    func testG3VcuFirmwareUsesPackedU16NotRawBytes() {
        var reading = IntegrityReading()
        let spec = DiagnosticMap.Spec(
            id: "g3_vcu_fw",
            board: .vcuG3,
            register: Nb.G3Register.vcuVersion,
            readLen: 2,
            category: .firmware
        )
        DiagnosticMap.apply(spec: spec, data: Data([0x61, 0x01]), into: &reading)
        XCTAssertEqual(reading.fwVcu, "1.6.1")
    }

    func testG3VcuFirmware157() {
        var reading = IntegrityReading()
        let spec = DiagnosticMap.Spec(
            id: "g3_vcu_fw",
            board: .vcuG3,
            register: Nb.G3Register.vcuVersion,
            readLen: 2,
            category: .firmware
        )
        DiagnosticMap.apply(spec: spec, data: Data([0x57, 0x01]), into: &reading)
        XCTAssertEqual(reading.fwVcu, "1.5.7")
    }

    func testRegisterScaleFirmwarePackedLayout() {
        XCTAssertEqual(RegisterScale.firmware(0x0161), "1.6.1")
        XCTAssertEqual(RegisterScale.firmware(0x0157), "1.5.7")
        XCTAssertEqual(RegisterScale.firmware(0x0164), "1.6.4")
        XCTAssertEqual(RegisterScale.firmware(0x0148), "1.4.8")
    }

    func testG3FirmwareMapHasNoFourByteVcuOverread() {
        let ids = DiagnosticMap.fields(for: .ninebotF3D).map(\.id)
        XCTAssertTrue(ids.contains("g3_vcu_fw"))
        XCTAssertFalse(ids.contains("g3_vcu_fw4"))
        let vcu = DiagnosticMap.fields(for: .maxG3D).first { $0.id == "g3_vcu_fw" }
        XCTAssertEqual(vcu?.readLen, 2)
    }

    func testDecodeDisplayMatchesPackedFirmware() {
        let spec = DiagnosticMap.Spec(
            id: "g3_vcu_fw",
            board: .vcuG3,
            register: Nb.G3Register.vcuVersion,
            readLen: 2,
            category: .firmware
        )
        XCTAssertEqual(DiagnosticMap.decode(spec: spec, data: Data([0x61, 0x01])), "1.6.1")
    }
}
