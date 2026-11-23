import XCTest
@testable import ScooterCheck

/// Logik-/UI-Führungs-Tests ohne reale BLE-/Server-Geräte (Testdoubles über Store).
@MainActor
final class InvestigationFlowLogicTests: XCTestCase {

    func testScooterOnlyThenFirmwareBecomesCombined() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowLogic-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InvestigationStore(testRoot: root)

        let rec = store.create(title: "Scooter Only", progress: .selectScooter)
        let summary = InvestigationReadoutSummary(
            id: "r", savedAt: Date(), protocolNumber: "P1", profileId: "maxG3D",
            modelLabel: "Max G3 D", manufacturer: "Segway-Ninebot", serial: "FLOW-1",
            fwVcu: "1", fwMcu: "1", fwBle: "1", fwEsc: nil,
            hardwareVersion: nil, controllerHint: nil, bleAdvertisementName: "NB",
            speedLimitKmh: 20, blePeripheralId: nil, historyEntryId: nil
        )
        _ = store.attachReadout(summary, to: rec.id)
        store.setProgress(.showResults, for: rec.id)
        XCTAssertEqual(store.record(id: rec.id)?.kind, .scooterOnly)
        XCTAssertFalse(store.record(id: rec.id)?.isResumable == true)

        let sha = String(repeating: "d", count: 64)
        let report = FirmwareForensicReport(
            id: "flow-fw",
            analyzedAt: Date(),
            originalFileName: "flow.bin",
            containerKind: .bareBinary,
            archiveByteCount: 8,
            archiveDigest: FirmwareFileDigest(md5: "d41d8cd98f00b204e9800998ecf8427e", sha256: sha, byteCount: 8, shannonEntropy: 1),
            meta: FirmwarePackageMeta(schemaVersion: 1, displayName: "flow", models: [], type: "VCU", compatible: [], declaredMd5: nil, declaredEncrypted: false, rawInfoJSON: nil),
            entries: [],
            primaryFirmwarePath: "flow.bin",
            crypto: FirmwareCryptoAssessment(status: .unknownFormat, detectedFormat: "bin", decryptionAvailable: false, decryptionNote: "", evidence: []),
            binary: FirmwareBinaryAnalysis(performed: false, unavailableReason: "unit", architecture: .unknown, vectorTableLikely: false, resetHandlerHint: nil, stringsSample: [], codeDataNotes: []),
            evidence: [],
            comparison: nil,
            verdict: .gray,
            verdictRationale: "unit",
            limits: [],
            vehicleContext: nil,
            vehicleLinkNotes: [],
            summary: "unit",
            deepAnalysis: nil,
            serverArtifacts: nil
        )
        _ = try store.attachFirmwareReport(report, originalData: Data([1, 2, 3, 4]), to: rec.id)
        XCTAssertEqual(store.record(id: rec.id)?.kind, .combined)
        XCTAssertEqual(store.record(id: rec.id)?.reconciledProgress, .showResults)
        XCTAssertFalse(store.record(id: rec.id)?.isResumable == true)
    }

    func testFirmwareOnlyThenScooterBecomesCombined() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowLogic2-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InvestigationStore(testRoot: root)
        let rec = store.create(title: "FW", progress: .selectFirmware)
        var mutated = store.record(id: rec.id)!
        mutated.firmwareRefs = [
            InvestigationFirmwareRef(
                id: "f", addedAt: Date(), analyzedAt: Date(), originalFileName: "a.bin",
                subjectSHA256: String(repeating: "e", count: 64), byteCount: 1, containerKind: "bareBinary",
                reportId: "r", reportFileName: "firmware-r.json", archivedBinaryFileName: nil,
                archiveStatus: "missing", archiveError: "no bytes", serverJobId: nil,
                analysisCompleteness: nil, packageDisplayName: nil, referenceTrust: nil
            )
        ]
        store.upsert(mutated)
        XCTAssertEqual(store.record(id: rec.id)?.kind, .firmwareOnly)

        let summary = InvestigationReadoutSummary(
            id: "s", savedAt: Date(), protocolNumber: nil, profileId: "zt3ProD",
            modelLabel: "ZT3 Pro D", manufacturer: nil, serial: "Z1",
            fwVcu: "1", fwMcu: nil, fwBle: nil, fwEsc: nil,
            hardwareVersion: nil, controllerHint: nil, bleAdvertisementName: nil,
            speedLimitKmh: nil, blePeripheralId: nil, historyEntryId: nil
        )
        _ = store.attachReadout(summary, to: rec.id)
        XCTAssertEqual(store.record(id: rec.id)?.kind, .combined)
    }

    func testInterruptedCombinedResumesAtFirmwareStep() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowLogic3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InvestigationStore(testRoot: root)
        let rec = store.create(title: "Combined", progress: .selectScooter)
        _ = store.attachReadout(
            InvestigationReadoutSummary(
                id: "s", savedAt: Date(), protocolNumber: nil, profileId: "zt3ProD",
                modelLabel: "ZT3 Pro D", manufacturer: nil, serial: "Z9",
                fwVcu: "1.5.5", fwMcu: "1.5.2", fwBle: "2.1.13", fwEsc: nil,
                hardwareVersion: nil, controllerHint: nil, bleAdvertisementName: nil,
                speedLimitKmh: 25, blePeripheralId: nil, historyEntryId: nil
            ),
            to: rec.id
        )
        store.setProgress(.selectFirmware, for: rec.id)
        let loaded = store.record(id: rec.id)!
        XCTAssertEqual(loaded.reconciledProgress, .selectFirmware)
        XCTAssertTrue(loaded.isResumable)
        XCTAssertTrue(loaded.resumeSubtitle.contains("Firmwaredatei"))
        XCTAssertEqual(CombinedInvestigationStep.from(progress: loaded.reconciledProgress), .pickFirmware)
    }
}
