import XCTest
@testable import ScootProof

final class IdentifyCommandTests: XCTestCase {

    func testWriteU16LookingForScooterFrame() {
        let frame = Nb.writeU16(
            board: .mcu,
            register: Nb.Identify.lookingForScooter,
            value: 1,
            noResponse: true,
            gen: .gen2
        )
        XCTAssertEqual(frame[0], Nb.sync1)
        XCTAssertEqual(frame[1], Nb.sync2BLE)
        XCTAssertEqual(frame[2], 2) // payload length
        XCTAssertEqual(frame[4], Nb.Board.mcu.rawValue)
        XCTAssertEqual(frame[5], Nb.Cmd.writeNR.rawValue)
        XCTAssertEqual(frame[6], Nb.Identify.lookingForScooter)
        XCTAssertEqual(frame[7], 0x01)
        XCTAssertEqual(frame[8], 0x00)
    }

    func testPlaySoundG3Register() {
        let frame = Nb.writeBytes(
            board: .vcuG3,
            register: Nb.Identify.playSound,
            data: Data([0x01, 0x00]),
            noResponse: true
        )
        XCTAssertEqual(frame[4], Nb.Board.vcuG3.rawValue)
        XCTAssertEqual(frame[6], Nb.Identify.playSound)
    }
}
