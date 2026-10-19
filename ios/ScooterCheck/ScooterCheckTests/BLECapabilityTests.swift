import XCTest
@testable import ScooterCheck

final class BLECapabilityTests: XCTestCase {
    func testDerivesImmediateAlertWhenWritable() {
        let caps = BLECapabilityDeriver.derive(
            services: ["00001802-0000-1000-8000-00805F9B34FB"],
            characteristics: [
                .init(
                    serviceUUID: "00001802-0000-1000-8000-00805F9B34FB",
                    uuid: "00002A06-0000-1000-8000-00805F9B34FB",
                    canWrite: false,
                    canWriteWithoutResponse: true
                ),
            ]
        )
        XCTAssertTrue(caps.supportsImmediateAlert)
        XCTAssertTrue(caps.alertPreferWriteWithoutResponse)
        XCTAssertTrue(caps.supportsAlert)
        XCTAssertTrue(caps.proximitySearchAvailable)
        XCTAssertTrue(caps.hasAnyDeviceAction)
    }

    func testImmediateAlertWithoutWriteIsNotActionable() {
        let caps = BLECapabilityDeriver.derive(
            services: ["1802"],
            characteristics: [
                .init(
                    serviceUUID: "1802",
                    uuid: "2A06",
                    canWrite: false,
                    canWriteWithoutResponse: false
                ),
            ]
        )
        XCTAssertFalse(caps.supportsImmediateAlert)
        XCTAssertFalse(caps.hasAnyDeviceAction)
    }

    func testNordicLedDetection() {
        let caps = BLECapabilityDeriver.derive(
            services: [BLECapabilityUUID.nordicLedButtonService],
            characteristics: [
                .init(
                    serviceUUID: BLECapabilityUUID.nordicLedButtonService,
                    uuid: BLECapabilityUUID.nordicLedCharacteristic,
                    canWrite: true,
                    canWriteWithoutResponse: false
                ),
            ]
        )
        XCTAssertTrue(caps.supportsNordicLed)
        XCTAssertTrue(caps.supportsVisualIdentification)
    }

    func testBatteryAndDisFlags() {
        let caps = BLECapabilityDeriver.derive(
            services: ["180F", "180A"],
            characteristics: [
                .init(serviceUUID: "180F", uuid: "2A19", canWrite: false, canWriteWithoutResponse: false),
            ]
        )
        XCTAssertTrue(caps.supportsBatteryReading)
        XCTAssertTrue(caps.supportsDeviceInformation)
        XCTAssertFalse(caps.hasAnyDeviceAction)
    }

    func testFingerprintStatusMapping() {
        XCTAssertEqual(BLEFingerprintStatus.from(confidence: .high), .identified)
        XCTAssertEqual(BLEFingerprintStatus.from(confidence: .medium), .likelyFamily)
        XCTAssertEqual(BLEFingerprintStatus.from(confidence: .low), .unknown)
        XCTAssertEqual(BLEFingerprintStatus.from(confidence: nil), .unknown)
    }

    func testUuidMatchShortAndFull() {
        XCTAssertTrue(BLECapabilityUUID.matches("00001802-0000-1000-8000-00805F9B34FB", shortOrFull: "1802"))
        XCTAssertTrue(BLECapabilityUUID.matches("2A06", shortOrFull: "2A06"))
        XCTAssertFalse(BLECapabilityUUID.matches("180F", shortOrFull: "1802"))
    }
}
