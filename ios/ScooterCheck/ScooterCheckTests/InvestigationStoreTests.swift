import XCTest
@testable import ScooterCheck

@MainActor
final class InvestigationStoreTests: XCTestCase {

    func testKindDerivesFromArtifacts() {
        var rec = InvestigationRecord(
            id: "t1",
            createdAt: Date(),
            updatedAt: Date(),
            title: "T",
            readout: nil,
            firmwareRefs: [],
            notes: []
        )
        XCTAssertEqual(rec.kind, .scooterOnly)
        XCTAssertFalse(rec.isValid)

        rec.readout = InvestigationReadoutSummary(
            id: "r1",
            savedAt: Date(),
            protocolNumber: "P-1",
            profileId: "maxG3D",
            modelLabel: "Max G3 D",
            serial: "SN1",
            fwVcu: "1.0.0",
            fwMcu: "1.0.1",
            fwBle: "2.0.0",
            fwEsc: nil,
            speedLimitKmh: 20,
            blePeripheralId: nil,
            historyEntryId: nil
        )
        XCTAssertEqual(rec.kind, .scooterOnly)
        XCTAssertTrue(rec.isValid)

        rec.firmwareRefs = [
            InvestigationFirmwareRef(
                id: "f1",
                addedAt: Date(),
                originalFileName: "fw.zip",
                subjectSHA256: "abc",
                reportId: "rep1",
                reportFileName: "firmware-rep1.json",
                analysisCompleteness: nil,
                packageDisplayName: nil
            )
        ]
        XCTAssertEqual(rec.kind, .combined)

        rec.readout = nil
        XCTAssertEqual(rec.kind, .firmwareOnly)
    }

    func testCombinedStepProgressLabels() {
        XCTAssertEqual(CombinedInvestigationStep.selectScooter.progressLabel, "Schritt 1 von 4")
        XCTAssertEqual(CombinedInvestigationStep.results.title, "Gemeinsame Ergebnisse")
        XCTAssertEqual(CombinedInvestigationStep.allCases.count, 4)
        XCTAssertEqual(InvestigationKind.scooterOnly.rawValue, "SCOOTER_ONLY")
        XCTAssertEqual(InvestigationKind.firmwareOnly.rawValue, "FIRMWARE_ONLY")
        XCTAssertEqual(InvestigationKind.combined.rawValue, "COMBINED")
    }

    func testStoreCreateAttachAndKindUpgrade() {
        let store = InvestigationStore.shared
        let before = store.records.count
        let rec = store.create(title: "UnitTest Investigation")
        XCTAssertFalse(rec.isValid)

        let summary = InvestigationReadoutSummary(
            id: UUID().uuidString,
            savedAt: Date(),
            protocolNumber: nil,
            profileId: "zt3ProD",
            modelLabel: "ZT3 Pro D",
            serial: "UNIT-SN",
            fwVcu: "1.5.5",
            fwMcu: "1.5.2",
            fwBle: "2.1.13",
            fwEsc: nil,
            speedLimitKmh: 25,
            blePeripheralId: nil,
            historyEntryId: nil
        )
        store.attachReadout(summary, to: rec.id)
        let afterReadout = store.record(id: rec.id)
        XCTAssertEqual(afterReadout?.kind, .scooterOnly)
        XCTAssertEqual(afterReadout?.readout?.serial, "UNIT-SN")

        var mutated = afterReadout!
        mutated.firmwareRefs.append(
            InvestigationFirmwareRef(
                id: UUID().uuidString,
                addedAt: Date(),
                originalFileName: "unit.bin",
                subjectSHA256: String(repeating: "a", count: 64),
                reportId: UUID().uuidString,
                reportFileName: "firmware-unit.json",
                analysisCompleteness: nil,
                packageDisplayName: "unit"
            )
        )
        store.upsert(mutated)
        XCTAssertEqual(store.record(id: rec.id)?.kind, .combined)

        // Second firmware must append, not overwrite the first.
        var again = store.record(id: rec.id)!
        again.firmwareRefs.append(
            InvestigationFirmwareRef(
                id: UUID().uuidString,
                addedAt: Date(),
                originalFileName: "unit-b.bin",
                subjectSHA256: String(repeating: "b", count: 64),
                reportId: UUID().uuidString,
                reportFileName: "firmware-unit-b.json",
                analysisCompleteness: nil,
                packageDisplayName: "unit-b"
            )
        )
        store.upsert(again)
        XCTAssertEqual(store.record(id: rec.id)?.firmwareRefs.count, 2)
        XCTAssertEqual(store.record(id: rec.id)?.kind, .combined)

        store.delete(id: rec.id)
        XCTAssertEqual(store.records.count, before)
    }
}
