import XCTest
@testable import ScooterCheck

final class ScooterVerificationTests: XCTestCase {

    // MARK: - Reading verification

    func testSupportedScooterWithSerialIsVerified() {
        let reading = IntegrityReading(
            serialDisplay: "1EFHE2515C0440",
            bleStack: BleStack.ninebotEnc2.rawValue,
            liveBoards: ["MCU", "BMS"]
        )
        XCTAssertTrue(ScooterVerification.isVerifiedScooterReading(reading))
    }

    func testSupportedScooterWithRegistersOnlyIsVerified() {
        let reading = IntegrityReading(
            bleStack: BleStack.ninebotEnc2.rawValue,
            rawRegisters: [
                RawRegister(address: "0x1A", name: "MCU", valueHex: "AABB")
            ]
        )
        XCTAssertTrue(ScooterVerification.isVerifiedScooterReading(reading))
    }

    func testEmptyReadingAfterFailedScanIsNotVerified() {
        let reading = IntegrityReading()
        XCTAssertFalse(ScooterVerification.isVerifiedScooterReading(reading))
    }

    func testEncryptedStackWithoutPayloadIsNotVerified() {
        let reading = IntegrityReading(bleStack: BleStack.xiaomiEncrypted.rawValue)
        XCTAssertFalse(ScooterVerification.isVerifiedScooterReading(reading))
    }

    func testNameAloneDoesNotVerify() {
        // „Scooter“ im Namen / leere Auslese → kein Verified.
        let reading = IntegrityReading(bleStack: BleStack.unknown.rawValue)
        XCTAssertFalse(ScooterVerification.isVerifiedScooterReading(reading))
        XCTAssertFalse(ScooterVerification.hasIdentitySerial(reading))
    }

    func testShortSerialIsNotIdentity() {
        let reading = IntegrityReading(serialDisplay: "TV123")
        XCTAssertFalse(ScooterVerification.hasIdentitySerial(reading))
        XCTAssertFalse(ScooterVerification.isVerifiedScooterReading(reading))
    }

    func testFirmwareAloneIsVerified() {
        let reading = IntegrityReading(fwMcu: "1.2.8_DE", bleStack: BleStack.xiaomiPlain.rawValue)
        XCTAssertTrue(ScooterVerification.isVerifiedScooterReading(reading))
    }

    // MARK: - Known-scooter qualification / legacy cleanup

    func testVerifiedFlagTrueQualifies() {
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-OK",
            createdAt: Date(),
            profile: .maxG3D,
            serialDisplay: "1EFHE2515C0440",
            wasVerifiedAsScooter: true
        )
        XCTAssertTrue(ScooterVerification.qualifiesAsKnownScooter(entry))
        XCTAssertEqual(entry.scanListAlias, "bereits geprüft")
    }

    func testVerifiedFlagFalseNeverQualifiesEvenWithSerial() {
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-BAD",
            createdAt: Date(),
            profile: .maxG3D,
            serialDisplay: "1EFHE2515C0440",
            blePeripheralId: UUID(),
            wasVerifiedAsScooter: false
        )
        XCTAssertFalse(ScooterVerification.qualifiesAsKnownScooter(entry))
        XCTAssertNil(entry.scanListAlias)
    }

    func testLegacyEntryWithSerialStillQualifies() {
        // Alte Einträge ohne Flag, aber mit echter SN aus Auslese.
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-LEGACY",
            createdAt: Date(),
            profile: .maxG3D,
            serialDisplay: "1CGBF2531C0230"
        )
        XCTAssertNil(entry.wasVerifiedAsScooter)
        XCTAssertTrue(ScooterVerification.qualifiesAsKnownScooter(entry))
    }

    func testLegacyBleOnlyEntryDoesNotQualify() {
        // TV-Fehllink: nur Peripheral-UUID, keine SN, kein Flag.
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-TV",
            createdAt: Date(),
            profile: .maxG3D,
            blePeripheralId: UUID(),
            bleAdvertisementName: "Samsung TV"
        )
        XCTAssertFalse(ScooterVerification.qualifiesAsKnownScooter(entry))
        XCTAssertNil(entry.scanListAlias)
    }

    func testLegacyScooterNamedWithoutSerialDoesNotQualify() {
        let entry = ProtocolHistoryStore.Entry(
            id: UUID(),
            protocolNumber: "SC-NAME",
            createdAt: Date(),
            profile: .maxG3D,
            blePeripheralId: UUID(),
            bleAdvertisementName: "My Scooter Pro"
        )
        XCTAssertFalse(ScooterVerification.qualifiesAsKnownScooter(entry))
    }

    func testEntryDecodesWasVerifiedFlag() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "protocolNumber": "SC-V",
          "createdAt": "2024-06-01T12:00:00Z",
          "profile": "maxG3D",
          "serialDisplay": "1EFHE2515C0440",
          "wasVerifiedAsScooter": true
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ProtocolHistoryStore.Entry.self, from: json)
        XCTAssertEqual(entry.wasVerifiedAsScooter, true)
        XCTAssertTrue(ScooterVerification.qualifiesAsKnownScooter(entry))
    }

    func testEntryDecodesMissingVerifiedFlagAsNil() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "protocolNumber": "SC-OLD",
          "createdAt": "2023-11-14T22:13:20Z",
          "profile": "maxG3D",
          "blePeripheralId": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ProtocolHistoryStore.Entry.self, from: json)
        XCTAssertNil(entry.wasVerifiedAsScooter)
        XCTAssertFalse(ScooterVerification.qualifiesAsKnownScooter(entry))
    }
}
