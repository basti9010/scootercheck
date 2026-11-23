import XCTest
@testable import ScooterCheck

@MainActor
final class BLECentralCoordinatorTests: XCTestCase {
    override func setUp() async throws {
        BLECentralCoordinator.resetForTests()
    }

    override func tearDown() async throws {
        BLECentralCoordinator.resetForTests()
    }

    func testSecondaryAcquireWhileExclusiveFails() throws {
        BLECentralCoordinator.beginBleClientExclusive()
        XCTAssertTrue(BLECentralCoordinator.isBleClientExclusive)
        XCTAssertThrowsError(try BLECentralCoordinator.acquire(.gattDeepAnalysis)) { error in
            guard case BLECentralCoordinator.LeaseError.busy(let owner) = error else {
                return XCTFail("expected busy(bleClient), got \(error)")
            }
            XCTAssertEqual(owner, .bleClient)
        }
        BLECentralCoordinator.endBleClientExclusive()
        XCTAssertNoThrow(try BLECentralCoordinator.acquire(.gattDeepAnalysis))
        BLECentralCoordinator.release(.gattDeepAnalysis)
    }

    func testCapabilityBlockedWhileGattHoldsLease() throws {
        try BLECentralCoordinator.acquire(.gattDeepAnalysis)
        XCTAssertThrowsError(try BLECentralCoordinator.acquire(.capabilityService))
        BLECentralCoordinator.release(.gattDeepAnalysis)
        XCTAssertNoThrow(try BLECentralCoordinator.acquire(.capabilityService))
        BLECentralCoordinator.release(.capabilityService)
    }

    func testReleaseIsIdempotentForOtherOwner() throws {
        try BLECentralCoordinator.acquire(.capabilityService)
        BLECentralCoordinator.release(.gattDeepAnalysis)
        XCTAssertEqual(BLECentralCoordinator.currentOwner, .capabilityService)
        BLECentralCoordinator.release(.capabilityService)
        XCTAssertNil(BLECentralCoordinator.currentOwner)
    }

    func testSecondaryConnectBlockedWhenExclusive() throws {
        try BLECentralCoordinator.acquire(.gattDeepAnalysis)
        XCTAssertTrue(BLECentralCoordinator.secondaryConnectAllowed(for: .gattDeepAnalysis))
        BLECentralCoordinator.beginBleClientExclusive()
        XCTAssertFalse(BLECentralCoordinator.secondaryConnectAllowed(for: .gattDeepAnalysis))
        XCTAssertFalse(BLECentralCoordinator.secondaryConnectAllowed(for: .capabilityService))
    }
}
