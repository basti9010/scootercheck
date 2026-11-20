import XCTest
@testable import ScooterCheck

@MainActor
final class BLERadarAlertGateTests: XCTestCase {

    func testOrdinaryAlertsRequireEnabledRadarAndUIOrBackground() {
        let radar = BLERadarService.shared
        radar.endSession()
        radar.setRadarUIVisible(false)

        XCTAssertFalse(radar.allowsOrdinaryRadarUserAlerts(forLocalNotification: true))
        XCTAssertFalse(radar.allowsOrdinaryRadarUserAlerts(forLocalNotification: false))

        radar.startSession(enableRadar: true)
        defer { radar.endSession() }

        // Foreground without radar UI → no ordinary alerts.
        radar.setRadarUIVisible(false)
        radar.setForeground(true)
        XCTAssertFalse(radar.allowsOrdinaryRadarUserAlerts(forLocalNotification: true))
        XCTAssertFalse(radar.allowsOrdinaryRadarUserAlerts(forLocalNotification: false))

        // Radar surface visible → allow (subject to notify setting).
        radar.setRadarUIVisible(true)
        let notify = BLERadarSessionStore.shared.settings.notifyScooterDetections
        XCTAssertEqual(radar.allowsOrdinaryRadarUserAlerts(forLocalNotification: false), notify)
        XCTAssertEqual(radar.allowsOrdinaryRadarUserAlerts(forLocalNotification: true), notify)

        radar.setRadarUIVisible(false)
    }

    func testDefaultMapSettingsStoreSightingsEnabled() {
        XCTAssertTrue(RadarMapSettings.default.storeSightings)
        XCTAssertTrue(RadarMapSettings.default.storeDeviceHistory)
        XCTAssertFalse(RadarMapSettings.default.storeLocation)
    }
}
