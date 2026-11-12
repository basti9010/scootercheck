import XCTest
@testable import ScooterCheck

final class NaveeProtocolTests: XCTestCase {

    func testReadFrameHasHeaderFooterAndChecksum() {
        let frame = NaveeProtocol.buildReadFrame(command: .serialNumber)
        let bytes = [UInt8](frame)
        XCTAssertEqual(bytes.first, 0x55)
        XCTAssertEqual(bytes[1], 0xAA)
        XCTAssertEqual(bytes[3], 0x74)
        XCTAssertEqual(bytes[bytes.count - 2], 0xFE)
        XCTAssertEqual(bytes.last, 0xFD)
        let body = Array(bytes.dropLast(2))
        let expectedSum = body.dropLast().reduce(0) { ($0 &+ Int($1)) } & 0xFF
        XCTAssertEqual(Int(body.last!), expectedSum)
    }

    func testForbiddenWritesIncludeSpeedAndLock() {
        XCTAssertTrue(NaveeProtocol.isForbiddenWrite(0x6B))
        XCTAssertTrue(NaveeProtocol.isForbiddenWrite(0x6E))
        XCTAssertTrue(NaveeProtocol.isForbiddenWrite(0x51))
        XCTAssertFalse(NaveeProtocol.isForbiddenWrite(0x74))
        XCTAssertFalse(NaveeProtocol.isForbiddenWrite(0x73))
        XCTAssertFalse(NaveeProtocol.isForbiddenWrite(0x70))
    }

    func testDecodeFirmwareBlocks() {
        let payload = Data("M1.0B2.0S3.0D4.0".utf8)
        let blocks = NaveeProtocol.decodeFirmwareBlocks(payload)
        XCTAssertEqual(blocks["meter"], "M1.0")
        XCTAssertEqual(blocks["bldc"], "B2.0")
        XCTAssertEqual(blocks["bms"], "S3.0")
        XCTAssertEqual(blocks["screen"], "D4.0")
    }

    func testDecodeSerial() {
        XCTAssertEqual(NaveeProtocol.decodeSerial(Data("NVE1234567890123".utf8)), "NVE1234567890123")
        XCTAssertNil(NaveeProtocol.decodeSerial(Data()))
    }
}
