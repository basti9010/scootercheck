import XCTest
@testable import ScooterCheck

final class PedelecEvaluationTests: XCTestCase {
    func testPilotGhostRiotIsDocumented() {
        let pilot = PedelecEvaluationCore.pilotGhostRiotEN
        XCTAssertEqual(pilot.brand, "GHOST")
        XCTAssertTrue(pilot.model.localizedCaseInsensitiveContains("RIOT"))
        XCTAssertTrue(pilot.motor.localizedCaseInsensitiveContains("CX"))
        XCTAssertEqual(pilot.displayHint, "Kiox 300")
        XCTAssertEqual(pilot.legalAssistLimitKmh, 25)
        XCTAssertFalse(pilot.notes.isEmpty)
        XCTAssertEqual(PedelecEvaluationCore.pilotModels.count, 1)
    }

    func testBoschManufacturerIdScoresHigh() {
        // Little-endian company id 0x02A6 → bytes A6 02
        let device = ScannedPedelecAdvertisement(
            id: UUID(),
            name: "Ohne Namen",
            cryptoName: "",
            rssi: -55,
            manufacturerDataHex: "A602010203"
        )
        let match = PedelecEvaluationCore.evaluate(device: device)
        XCTAssertEqual(match.confidence, .high)
        XCTAssertGreaterThanOrEqual(match.score, 70)
        XCTAssertFalse(match.deepReadoutAvailable)
        XCTAssertTrue(match.reasons.contains(where: { $0.contains("0x02A6") }))
    }

    func testGhostNameTokenIsCandidate() {
        let device = ScannedPedelecAdvertisement(
            id: UUID(),
            name: "GHOST eBike Remote",
            cryptoName: "GHOST eBike Remote",
            rssi: -62
        )
        let match = PedelecEvaluationCore.evaluate(device: device)
        XCTAssertNotEqual(match.confidence, .none)
        XCTAssertGreaterThanOrEqual(match.score, 35)
    }

    func testUnrelatedDeviceIsIgnored() {
        let device = ScannedPedelecAdvertisement(
            id: UUID(),
            name: "AirPods Pro",
            cryptoName: "AirPods Pro",
            rssi: -40,
            manufacturerDataHex: "4C001122"
        )
        let match = PedelecEvaluationCore.evaluate(device: device)
        XCTAssertEqual(match.confidence, .none)
        XCTAssertEqual(match.score, 0)
    }

    func testRankedCandidatesSortByScoreThenRssi() {
        let weak = ScannedPedelecAdvertisement(
            id: UUID(),
            name: "Flow",
            cryptoName: "Flow",
            rssi: -40
        )
        let strong = ScannedPedelecAdvertisement(
            id: UUID(),
            name: "Device",
            cryptoName: "",
            rssi: -70,
            manufacturerDataHex: "A602FF"
        )
        let ranked = PedelecEvaluationCore.rankedCandidates(from: [weak, strong])
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(ranked.first?.device.id, strong.id)
    }

    func testCapabilitySummaryMentionsGattAndBoschGap() {
        let text = PedelecEvaluationCore.readoutCapabilitySummary.lowercased()
        XCTAssertTrue(text.contains("gatt") || text.contains("auslesen"))
        XCTAssertTrue(text.contains("bosch"))
        XCTAssertTrue(text.contains("nicht") || text.contains("noch"))
    }
}
