import XCTest
@testable import ScooterCheck

final class Enc2PairingPasswordTests: XCTestCase {
    private let testKeyPrefix = "ninebot_password_"

    override func tearDown() {
        BleClient.clearAllStoredPairingPasswords()
        super.tearDown()
    }

    func testClearAllStoredPairingPasswordsRemovesOnlyEnc2Keys() {
        let defaults = UserDefaults.standard
        let keepKey = "app.settings.textSize.v1"
        let previousKeep = defaults.object(forKey: keepKey)
        defaults.set("standard", forKey: keepKey)
        defaults.set(Data(repeating: 0xAB, count: 16), forKey: testKeyPrefix + "DEVICE-A")
        defaults.set(Data(repeating: 0xCD, count: 16), forKey: testKeyPrefix + "DEVICE-B")
        defaults.set("leave-me", forKey: "unrelated.setting")

        XCTAssertEqual(BleClient.storedPairingPasswordCount(), 2)
        let removed = BleClient.clearAllStoredPairingPasswords()
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(BleClient.storedPairingPasswordCount(), 0)
        XCTAssertEqual(defaults.string(forKey: "unrelated.setting"), "leave-me")
        XCTAssertEqual(defaults.string(forKey: keepKey), "standard")

        defaults.removeObject(forKey: "unrelated.setting")
        if let previousKeep {
            defaults.set(previousKeep, forKey: keepKey)
        } else {
            defaults.removeObject(forKey: keepKey)
        }
    }
}
