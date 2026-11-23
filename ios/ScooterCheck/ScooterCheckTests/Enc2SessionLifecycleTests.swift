import XCTest
@testable import ScooterCheck

final class Enc2SessionLifecycleTests: XCTestCase {
    func testInactiveNotAuthenticated() {
        XCTAssertFalse(Enc2SessionLifecycle.inactive.isAuthenticatedForDump)
    }

    func testCryptoAloneInsufficientWithoutAlive() {
        let state = Enc2SessionLifecycle(alive: false, hasCrypto: true, peripheralConnected: true)
        XCTAssertFalse(state.isAuthenticatedForDump)
    }

    func testConnectedAliveWithoutCryptoInsufficient() {
        let state = Enc2SessionLifecycle(alive: true, hasCrypto: false, peripheralConnected: true)
        XCTAssertFalse(state.isAuthenticatedForDump)
    }

    func testHandshakeThenDisconnectInvalidates() {
        let live = Enc2SessionLifecycle.inactive.markingHandshakeSucceeded()
        XCTAssertTrue(live.isAuthenticatedForDump)
        let dead = live.invalidated()
        XCTAssertFalse(dead.isAuthenticatedForDump)
        XCTAssertFalse(dead.alive)
        XCTAssertFalse(dead.hasCrypto)
    }

    func testDisconnectedPeripheralBlocksDumpReuse() {
        let state = Enc2SessionLifecycle(alive: true, hasCrypto: true, peripheralConnected: false)
        XCTAssertFalse(state.isAuthenticatedForDump)
    }
}
