import XCTest
@testable import ScooterCheck

final class LiveTelemetryTests: XCTestCase {

    func testG3LiveFieldsCoverDarknessBotCore() {
        let ids = Set(DiagnosticMap.liveTelemetryFields(for: .maxG3D).map(\.id))
        XCTAssertTrue(ids.contains("vcu_g3_speed"))
        XCTAssertTrue(ids.contains("vcu_g3_battery"))
        XCTAssertTrue(ids.contains("bms_g3_voltage"))
        XCTAssertTrue(ids.contains("bms_g3_current"))
        XCTAssertTrue(ids.contains("vcu_g3_bodytemp"))
        XCTAssertTrue(ids.contains("bms_g3_temp"))
        XCTAssertTrue(ids.contains("vcu_g3_remain"))
        XCTAssertTrue(ids.contains("vcu_g3_trip"))
        XCTAssertTrue(ids.contains("vcu_g3_runtime_trip"))
    }

    func testDumpIncludesNewBatteryAndTempRegisters() {
        let ids = Set(DiagnosticMap.fields(for: .gt3D).map(\.id))
        XCTAssertTrue(ids.contains("bms_g3_current"))
        XCTAssertTrue(ids.contains("bms_g3_temp"))
        XCTAssertTrue(ids.contains("vcu_g3_bodytemp"))
        XCTAssertTrue(ids.contains("vcu_g3_runtime_trip"))
        XCTAssertTrue(ids.contains("bms_g3_maxpower"))
    }

    func testBmsTempDecodeOffset20() {
        let data = Data([45, 48, 0, 0]) // 25 °C / 28 °C
        XCTAssertEqual(DiagnosticMap.decodeBmsTempC(data), 25, accuracy: 0.1)
    }

    func testLiveSnapshotAppliesCurrentAndPower() {
        var snap = LiveTelemetrySnapshot()
        let volt = SpecApply.u16LE(5200) // 52.00 V
        let cur = SpecApply.i16LE(-150) // -1.50 A
        snap.apply(
            spec: DiagnosticMap.Spec(id: "bms_g3_voltage", board: .bmsG3, register: 0x8C, readLen: 2, category: .live),
            data: volt
        )
        snap.apply(
            spec: DiagnosticMap.Spec(id: "bms_g3_current", board: .bmsG3, register: 0x8D, readLen: 2, category: .live),
            data: cur
        )
        XCTAssertEqual(snap.voltageV ?? 0, 52.0, accuracy: 0.01)
        XCTAssertEqual(snap.currentA ?? 0, -1.5, accuracy: 0.01)
        XCTAssertEqual(snap.powerW ?? 0, 78.0, accuracy: 0.5)
    }

    func testApplyBodyTempIntoReading() {
        var reading = IntegrityReading()
        let data = SpecApply.i16LE(265) // 26.5 °C
        let spec = DiagnosticMap.Spec(
            id: "vcu_g3_bodytemp",
            board: .vcuG3,
            register: Nb.G3Register.bodyTemp,
            readLen: 2,
            category: .history
        )
        DiagnosticMap.apply(spec: spec, data: data, into: &reading)
        XCTAssertEqual(reading.mcuTempC ?? 0, 26.5, accuracy: 0.05)
    }
}

private enum SpecApply {
    static func u16LE(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }

    static func i16LE(_ value: Int16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }
}
