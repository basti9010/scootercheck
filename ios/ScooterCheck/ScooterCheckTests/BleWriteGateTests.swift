import XCTest
@testable import ScooterCheck

final class BleWriteGateTests: XCTestCase {
    func testAllowVehicleManipulationIsHardFalse() {
        XCTAssertFalse(BleWriteGate.allowVehicleManipulation)
    }

    func testVehicleManipulationDenied() {
        XCTAssertFalse(BleWriteGate.isAllowed(.vehicleManipulation))
        XCTAssertFalse(BleWriteGate.authorize(.vehicleManipulation))
        XCTAssertFalse(BleWriteGate.isAllowed(.unknown))
        XCTAssertFalse(BleWriteGate.authorize(.unknown))
    }

    func testIdentifyAuthAndCapabilityAllowed() {
        XCTAssertTrue(BleWriteGate.authorize(.enc2Auth))
        XCTAssertTrue(BleWriteGate.authorize(.identifyFind))
        XCTAssertTrue(BleWriteGate.authorize(.capabilityAlert))
        XCTAssertTrue(BleWriteGate.authorize(.capabilityNordicLed))
        XCTAssertTrue(BleWriteGate.isAllowed(.enc2Auth))
        XCTAssertTrue(BleWriteGate.isAllowed(.identifyFind))
        XCTAssertTrue(BleWriteGate.isAllowed(.capabilityAlert))
        XCTAssertTrue(BleWriteGate.isAllowed(.capabilityNordicLed))
    }
}
