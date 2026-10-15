import XCTest
@testable import ScootProof

final class RawDumpHighlighterTests: XCTestCase {

    func testSourceLineFormat() {
        let reg = RawRegister(
            address: "22-46",
            name: "vcu_g3_maxspd",
            valueHex: "0023",
            valueDecoded: "35.0 km/h"
        )
        let line = RawDumpHighlighter.formatSourceLine(reg)
        XCTAssertTrue(line.contains("vcu_g3_maxspd = 35.0 km/h"), line)
        XCTAssertTrue(line.contains("22-46"), line)
        XCTAssertTrue(line.contains("0023"), line)
    }

    func testElevatedLimitIsMarkedRedWithBracketExplanation() {
        let reading = IntegrityReading(
            serialDisplay: "1EFHE2515C0440",
            speedLimitKmh: 35,
            peakSpeedKmh: 25,
            rawRegisters: [
                RawRegister(address: "22-46", name: "vcu_g3_maxspd", valueHex: "0023", valueDecoded: "35.0 km/h"),
                RawRegister(address: "22-45", name: "vcu_g3_edmax", valueHex: "0C14", valueDecoded: "20.0 km/h"),
                RawRegister(address: "22-24", name: "vcu_g3_trip_max", valueHex: "3543", valueDecoded: "67.0 km/h"),
                RawRegister(address: "4-01", name: "g3_ble_fw", valueHex: "4500", valueDecoded: "0.4.5")
            ]
        )
        let evidence = EvidenceEngine.evaluate(reading: reading, profile: .ninebotF3D)
        let lines = RawDumpHighlighter.lines(reading: reading, evidence: evidence)

        let maxspd = try XCTUnwrap(lines.first { $0.register.name == "vcu_g3_maxspd" })
        let ann = try XCTUnwrap(maxspd.annotation)
        XCTAssertEqual(ann.severity, .decisive)
        XCTAssertTrue(ann.bracketLabel.localizedCaseInsensitiveContains("Limit"), ann.bracketLabel)
        XCTAssertTrue(ann.explanation.localizedCaseInsensitiveContains("Tacho"), ann.explanation)
        XCTAssertTrue(maxspd.annotatedSourceLine.contains("["))
        XCTAssertTrue(maxspd.annotatedSourceLine.contains("Limit"))

        let edmax = try XCTUnwrap(lines.first { $0.register.name == "vcu_g3_edmax" })
        XCTAssertEqual(edmax.annotation?.severity, .note)
        XCTAssertTrue(edmax.annotation?.explanation.localizedCaseInsensitiveContains("Fahrgefühl") == true)
    }

    func testStockDumpHasNoDecisiveHighlights() {
        let reading = IntegrityReading(
            serialDisplay: "1CGBTEST0001",
            speedLimitKmh: 20,
            peakSpeedKmh: 18,
            fwMcu: "1.4.12",
            fwBle: "0.3.14",
            fwVcu: "1.5.8",
            gearMax: 1,
            rawRegisters: [
                RawRegister(address: "22-46", name: "vcu_g3_maxspd", valueHex: "1400", valueDecoded: "20.0 km/h"),
                RawRegister(address: "22-24", name: "vcu_g3_trip_max", valueHex: "1200", valueDecoded: "18.0 km/h")
            ]
        )
        let evidence = EvidenceEngine.evaluate(reading: reading, profile: .maxG3D)
        let lines = RawDumpHighlighter.lines(reading: reading, evidence: evidence)
        XCTAssertFalse(lines.contains { $0.annotation?.severity == .decisive })
    }
}
