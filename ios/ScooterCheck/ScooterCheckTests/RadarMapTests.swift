import XCTest
@testable import ScooterCheck

@MainActor
final class RadarMapTests: XCTestCase {

    override func setUp() async throws {
        RadarMapStore.shared.deleteAllSightings()
        for h in RadarMapStore.shared.hidden {
            RadarMapStore.shared.unhideDevice(hiddenId: h.id)
        }
        var s = RadarMapSettings.default
        s.storeSightings = true
        s.storeLocation = false
        s.sightingGapMinutes = 15
        s.retentionHours = nil
        RadarMapStore.shared.settings = s
    }

    func testAggregationSameBurstIsOneSighting() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identity = RadarDeviceIdentity(
            id: UUID(),
            primaryPeripheralId: UUID(),
            fingerprintKey: "test|mfg|svc|struct",
            displayName: "Test Scooter",
            manufacturer: "KuKirin",
            model: "G4",
            firstSeenAt: Date(),
            lastSeenAt: Date(),
            sightingCount: 0,
            deviceKind: .possibleScooter,
            approvalStatusRaw: nil
        )
        store.upsertIdentity(identity)

        let t0 = Date()
        var sighting = RadarSighting(
            id: UUID(),
            sessionId: session.id,
            deviceIdentityId: identity.id,
            peripheralId: identity.primaryPeripheralId,
            fingerprintKey: identity.fingerprintKey,
            displayName: "Test Scooter",
            manufacturer: "KuKirin",
            model: "G4",
            identificationConfidence: .medium,
            identityMatchConfidence: .confirmed,
            firstSeenAt: t0,
            lastSeenAt: t0,
            observationCount: 1,
            strongestRSSI: -60,
            averageRSSI: -60,
            smoothedRSSI: nil,
            location: nil,
            serviceUUIDs: [],
            manufacturerDataHex: nil,
            approvalStatusRaw: nil,
            deviceKind: .possibleScooter
        )
        store.upsertSighting(sighting)
        // Simulate 100 packets within gap → same sighting updated
        for i in 1..<100 {
            sighting.lastSeenAt = t0.addingTimeInterval(Double(i) * 0.2)
            sighting.observationCount = i + 1
            sighting.strongestRSSI = -50
            store.upsertSighting(sighting)
        }
        XCTAssertEqual(store.sightings(forIdentity: identity.id).count, 1)
        XCTAssertEqual(store.sightings.first?.observationCount, 100)
    }

    func testGapCreatesSecondSighting() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identityId = UUID()
        let peripheral = UUID()
        let t0 = Date()
        let s1 = makeSighting(session: session.id, identity: identityId, peripheral: peripheral, at: t0)
        store.upsertSighting(s1)
        let s2 = makeSighting(
            session: session.id,
            identity: identityId,
            peripheral: peripheral,
            at: t0.addingTimeInterval(30 * 60)
        )
        store.upsertSighting(s2)
        XCTAssertEqual(store.sightings(forIdentity: identityId).count, 2)
    }

    func testRepeatFilterRequiresSeparateSightings() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identityId = UUID()
        let peripheral = UUID()
        let t0 = Date()
        store.upsertSighting(makeSighting(session: session.id, identity: identityId, peripheral: peripheral, at: t0))
        var filter = RadarMapFilter()
        filter.onlyRepeated = true
        filter.minSightings = 2
        XCTAssertTrue(store.filteredSightings(filter: filter).isEmpty)

        store.upsertSighting(makeSighting(
            session: session.id,
            identity: identityId,
            peripheral: peripheral,
            at: t0.addingTimeInterval(3600)
        ))
        XCTAssertEqual(store.filteredSightings(filter: filter).count, 2)
    }

    func testDeleteSightingKeepsOthers() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identityId = UUID()
        let peripheral = UUID()
        let a = makeSighting(session: session.id, identity: identityId, peripheral: peripheral, at: Date())
        let b = makeSighting(session: session.id, identity: identityId, peripheral: peripheral, at: Date().addingTimeInterval(3600))
        store.upsertSighting(a)
        store.upsertSighting(b)
        store.deleteSighting(id: a.id)
        XCTAssertEqual(store.sightings(forIdentity: identityId).count, 1)
        XCTAssertEqual(store.sightings(forIdentity: identityId).first?.id, b.id)
    }

    func testDeleteEntireHistoryByIdentity() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identityId = UUID()
        let peripheral = UUID()
        store.upsertSighting(makeSighting(session: session.id, identity: identityId, peripheral: peripheral, at: Date()))
        store.upsertSighting(makeSighting(session: session.id, identity: identityId, peripheral: peripheral, at: Date().addingTimeInterval(3600)))
        XCTAssertEqual(store.sightingCount(for: store.sightings.first!), 2)
        store.deleteHistory(forIdentity: identityId)
        XCTAssertTrue(store.sightings(forIdentity: identityId).isEmpty)
    }

    func testHideDoesNotDeleteSightings() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identityId = UUID()
        let peripheral = UUID()
        var s = makeSighting(session: session.id, identity: identityId, peripheral: peripheral, at: Date())
        s.identityMatchConfidence = .confirmed
        store.upsertSighting(s)
        store.hideDevice(from: s)
        var filter = RadarMapFilter()
        filter.showHidden = false
        XCTAssertTrue(store.filteredSightings(filter: filter).isEmpty)
        filter.showHidden = true
        XCTAssertEqual(store.filteredSightings(filter: filter).count, 1)
        XCTAssertEqual(store.sightings.count, 1)
        if let entry = store.hiddenEntry(identityId: identityId, peripheralId: peripheral) {
            store.unhideDevice(hiddenId: entry.id)
        }
        filter.showHidden = false
        XCTAssertEqual(store.filteredSightings(filter: filter).count, 1)
    }

    func testUncertainIdentityHidesOnlyPeripheral() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let peripheralA = UUID()
        let peripheralB = UUID()
        var a = makeSighting(session: session.id, identity: nil, peripheral: peripheralA, at: Date())
        a.identityMatchConfidence = .possible
        a.deviceIdentityId = nil
        var b = makeSighting(session: session.id, identity: nil, peripheral: peripheralB, at: Date())
        b.identityMatchConfidence = .possible
        b.deviceIdentityId = nil
        b.manufacturer = a.manufacturer
        store.upsertSighting(a)
        store.upsertSighting(b)
        store.hideDevice(from: a)
        XCTAssertTrue(store.isHidden(identityId: nil, peripheralId: peripheralA))
        XCTAssertFalse(store.isHidden(identityId: nil, peripheralId: peripheralB))
        XCTAssertEqual(store.hidden.first?.identityBound, false)
    }

    func testSuppressAlertsForHidden() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identityId = UUID()
        let peripheral = UUID()
        var s = makeSighting(session: session.id, identity: identityId, peripheral: peripheral, at: Date())
        s.identityMatchConfidence = .confirmed
        store.upsertSighting(s)
        store.hideDevice(from: s)
        XCTAssertTrue(store.shouldSuppressRadarAlerts(identityId: identityId, peripheralId: peripheral))
    }

    func testPossibleMatchDoesNotCountAsRepeat() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identityId = UUID()
        var a = makeSighting(session: session.id, identity: identityId, peripheral: UUID(), at: Date())
        a.identityMatchConfidence = .possible
        var b = makeSighting(session: session.id, identity: identityId, peripheral: UUID(), at: Date().addingTimeInterval(3600))
        b.identityMatchConfidence = .possible
        store.upsertSighting(a)
        store.upsertSighting(b)
        var filter = RadarMapFilter()
        filter.onlyRepeated = true
        filter.minSightings = 2
        // possible matches must not satisfy repeat filter
        XCTAssertTrue(store.filteredSightings(filter: filter).isEmpty)
    }

    func testTimeFilter() {
        let store = RadarMapStore.shared
        let session = store.upsertSession(RadarMapSession(id: UUID(), startedAt: Date(), endedAt: nil))
        let identityId = UUID()
        let old = makeSighting(
            session: session.id,
            identity: identityId,
            peripheral: UUID(),
            at: Date().addingTimeInterval(-3 * 24 * 3600)
        )
        let recent = makeSighting(session: session.id, identity: identityId, peripheral: UUID(), at: Date())
        store.upsertSighting(old)
        store.upsertSighting(recent)
        var filter = RadarMapFilter()
        filter.timePreset = .h24
        let list = store.filteredSightings(filter: filter)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, recent.id)
    }

    private func makeSighting(
        session: UUID,
        identity: UUID?,
        peripheral: UUID,
        at: Date
    ) -> RadarSighting {
        RadarSighting(
            id: UUID(),
            sessionId: session,
            deviceIdentityId: identity,
            peripheralId: peripheral,
            fingerprintKey: "k",
            displayName: "Device",
            manufacturer: "KuKirin",
            model: "G4",
            identificationConfidence: .medium,
            identityMatchConfidence: .confirmed,
            firstSeenAt: at,
            lastSeenAt: at,
            observationCount: 1,
            strongestRSSI: -55,
            averageRSSI: -55,
            smoothedRSSI: nil,
            location: RadarLocationSample(
                latitude: 52.5,
                longitude: 13.4,
                horizontalAccuracy: 20,
                timestamp: at
            ),
            serviceUUIDs: [],
            manufacturerDataHex: nil,
            approvalStatusRaw: nil,
            deviceKind: .possibleScooter
        )
    }
}
