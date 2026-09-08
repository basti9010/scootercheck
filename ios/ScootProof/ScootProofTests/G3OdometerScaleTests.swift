import XCTest
@testable import ScootProof

final class G3OdometerScaleTests: XCTestCase {

    func testG3TotalMileageUsesTenthsNotMetres() {
        // Rohwert wie bei falsch /1000 → 25.5 km; korrekt /10 → 2550 km.
        let raw: UInt32 = 25_500
        XCTAssertEqual(RegisterScale.g3TotalMileageKm(raw), 2_550, accuracy: 0.01)
        XCTAssertNotEqual(RegisterScale.km(raw), RegisterScale.g3TotalMileageKm(raw))
    }

    func testG3TripMileageTenths() {
        XCTAssertEqual(RegisterScale.g3TripMileageKm(255), 25.5, accuracy: 0.01)
    }

    func testApplyVcuG3OdoOverridesWrongLegacyScale() {
        var reading = IntegrityReading()
        // Zuerst falsche Meter-Interpretation eines Tenths-Rohwerts.
        let raw = Data([0x9C, 0x63, 0x00, 0x00]) // 25500 LE
        let legacy = DiagnosticMap.Spec(
            id: "dis_odo",
            board: .dis,
            register: Nb.Register.odometer,
            readLen: 4,
            category: .history
        )
        DiagnosticMap.apply(spec: legacy, data: raw, into: &reading)
        XCTAssertEqual(reading.odometerKm ?? -1, 25.5, accuracy: 0.05)

        let g3 = DiagnosticMap.Spec(
            id: "vcu_g3_odo",
            board: .vcuG3,
            register: Nb.G3Register.totalMileage,
            readLen: 4,
            category: .history
        )
        DiagnosticMap.apply(spec: g3, data: raw, into: &reading)
        XCTAssertEqual(reading.odometerKm ?? -1, 2_550, accuracy: 0.05)
    }

    func testLegacyMetresStillWorksForClassicOdo() {
        // 123.456 km in Metern = 123456
        var bytes = Data()
        let raw: UInt32 = 123_456
        bytes.append(UInt8(raw & 0xFF))
        bytes.append(UInt8((raw >> 8) & 0xFF))
        bytes.append(UInt8((raw >> 16) & 0xFF))
        bytes.append(UInt8((raw >> 24) & 0xFF))
        var reading = IntegrityReading()
        let spec = DiagnosticMap.Spec(
            id: "dis_odo",
            board: .dis,
            register: Nb.Register.odometer,
            readLen: 4,
            category: .history
        )
        DiagnosticMap.apply(spec: spec, data: bytes, into: &reading)
        XCTAssertEqual(reading.odometerKm ?? -1, 123.456, accuracy: 0.001)
    }
}
