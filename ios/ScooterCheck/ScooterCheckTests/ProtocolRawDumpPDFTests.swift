import XCTest
@testable import ScooterCheck

final class ProtocolRawDumpPDFTests: XCTestCase {

    func testRegistersWithContentFiltersEmptyAndSorts() {
        var reading = IntegrityReading()
        reading.rawRegisters = [
            RawRegister(address: "VCU", index: 0x20, name: "b", valueHex: "0A0B"),
            RawRegister(address: "BLE", index: 0x01, name: "a", valueHex: "  "),
            RawRegister(address: "BLE", index: 0x02, name: "c", valueHex: "FF"),
            RawRegister(address: "BLE", index: 0x01, name: "z", valueHex: ""),
            RawRegister(address: "MCU", index: 0x10, name: "m", valueHex: "01", valueDecoded: "1"),
        ]
        let regs = ProtocolPDF.registersWithContent(from: reading)
        XCTAssertEqual(regs.map(\.name), ["c", "m", "b"])
        XCTAssertEqual(regs.map(\.address), ["BLE", "MCU", "VCU"])
    }

    func testRawPdfRendersWithoutVerdictAndContainsHex() throws {
        var reading = IntegrityReading()
        reading.serialDisplay = "1CGBTESTRAW001"
        reading.speedLimitKmh = 25
        reading.rawRegisters = [
            RawRegister(address: "VCU", index: 0x46, name: "maxspd", valueHex: "1900", valueDecoded: "25 km/h"),
            RawRegister(address: "BLE", index: 0x1A, name: "sn", valueHex: "31434742", valueDecoded: "1CGB"),
            RawRegister(address: "MCU", index: 0x01, name: "empty", valueHex: ""),
        ]
        let result = IntegrityAnalyzer.analyze(reading: reading, profile: .maxG3D)
        let session = CheckSession(profile: .maxG3D, result: result)
        let data = try ProtocolPDF.renderRawRegisters(session: session, result: result)
        XCTAssertGreaterThan(data.count, 500)
        // PDF magic
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")

        let pack = try ProtocolPack.makePack(session: session, result: result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pack.rawPdfURL.path))
        XCTAssertTrue(pack.rawPdfURL.lastPathComponent.contains("Rohdaten"))
        let rawBytes = try Data(contentsOf: pack.rawPdfURL)
        XCTAssertEqual(String(data: rawBytes.prefix(4), encoding: .ascii), "%PDF")
    }
}
