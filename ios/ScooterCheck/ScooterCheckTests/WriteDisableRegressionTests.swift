import XCTest
@testable import ScooterCheck

/// Regression: SoftUnlock stays observational; vehicle writes stay denied; Navee forbidden cmds stay blocked.
final class WriteDisableRegressionTests: XCTestCase {
    func testSoftUnlockIsObservationalThresholdOnly() {
        // SoftUnlock must not gain a BleWritePurpose that authorizes vehicle writes.
        XCTAssertFalse(BleWriteGate.authorize(.vehicleManipulation))
        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        XCTAssertGreaterThan(threshold, 0)
        // Enabled snapshot is detection UI — not a BLE write switch.
        _ = SoftUnlockSettings.isEnabledSnapshot()
    }

    func testNaveeForbiddenWritesCoverLimitLockDfuFamily() {
        let forbidden: [UInt8] = [
            NaveeProtocol.ForbiddenWriteCommand.unbind.rawValue,
            NaveeProtocol.ForbiddenWriteCommand.lock.rawValue,
            NaveeProtocol.ForbiddenWriteCommand.cruise.rawValue,
            NaveeProtocol.ForbiddenWriteCommand.energyRecovery.rawValue,
            NaveeProtocol.ForbiddenWriteCommand.lights.rawValue,
            NaveeProtocol.ForbiddenWriteCommand.restoreVehicle.rawValue,
            NaveeProtocol.ForbiddenWriteCommand.customSpeedLimit.rawValue,
            NaveeProtocol.ForbiddenWriteCommand.setSpeedOrMode.rawValue,
            NaveeProtocol.ForbiddenWriteCommand.setParams.rawValue
        ]
        for cmd in forbidden {
            XCTAssertTrue(
                NaveeProtocol.isForbiddenWrite(cmd),
                "Navee cmd 0x\(String(cmd, radix: 16)) must stay forbidden"
            )
        }
        // Benign read commands must not be classified as forbidden writes.
        XCTAssertFalse(NaveeProtocol.isForbiddenWrite(NaveeProtocol.ReadCommand.serialNumber.rawValue))
        XCTAssertFalse(NaveeProtocol.isForbiddenWrite(NaveeProtocol.ReadCommand.firmware.rawValue))
        XCTAssertFalse(BleWriteGate.authorize(.vehicleManipulation))
    }

    func testBleWriteGateAllowlistIsClosed() {
        let allowed: [BleWritePurpose] = [
            .enc2Auth, .identifyFind, .capabilityAlert, .capabilityNordicLed
        ]
        for purpose in allowed {
            XCTAssertTrue(BleWriteGate.authorize(purpose), "\(purpose) should stay allowlisted")
        }
        XCTAssertFalse(BleWriteGate.authorize(.vehicleManipulation))
        XCTAssertFalse(BleWriteGate.authorize(.unknown))
        XCTAssertFalse(BleWriteGate.allowVehicleManipulation)
    }
}
