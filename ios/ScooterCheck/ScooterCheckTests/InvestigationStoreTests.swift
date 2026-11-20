import XCTest
@testable import ScooterCheck

@MainActor
final class InvestigationStoreTests: XCTestCase {

    private var tempRoot: URL!
    private var store: InvestigationStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvestigationStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = InvestigationStore(testRoot: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        store = nil
        tempRoot = nil
        super.tearDown()
    }

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

        rec.readout = makeSummary(serial: "SN1")
        XCTAssertEqual(rec.kind, .scooterOnly)
        XCTAssertTrue(rec.isValid)
        XCTAssertEqual(rec.reconciledProgress, .showResults)
        rec.progress = .selectFirmware
        XCTAssertEqual(rec.reconciledProgress, .selectFirmware)

        rec.firmwareRefs = [makeRef(name: "fw.zip", sha: "abc", reportId: "rep1")]
        XCTAssertEqual(rec.kind, .combined)
        XCTAssertEqual(rec.reconciledProgress, .showResults)

        rec.readout = nil
        XCTAssertEqual(rec.kind, .firmwareOnly)
    }

    func testCombinedStepProgressLabels() {
        XCTAssertEqual(CombinedInvestigationStep.selectScooter.progressLabel, "Schritt 1 von 4")
        XCTAssertEqual(CombinedInvestigationStep.results.title, "Gemeinsame Ergebnisse")
        XCTAssertEqual(CombinedInvestigationStep.allCases.count, 4)
        XCTAssertEqual(InvestigationKind.scooterOnly.rawValue, "SCOOTER_ONLY")
        XCTAssertEqual(InvestigationProgress.selectFirmware.rawValue, "SELECT_FIRMWARE")
    }

    func testStoreCreateAttachArchiveAndReload() throws {
        let rec = store.create(title: "UnitTest Investigation", progress: .selectScooter)
        let summary = makeSummary(serial: "UNIT-SN")
        _ = store.attachReadout(summary, to: rec.id)
        XCTAssertEqual(store.record(id: rec.id)?.kind, .scooterOnly)

        let report = makeReport(id: "rep-a", fileName: "unit.bin", sha: String(repeating: "a", count: 64))
        let bytes = Data((0..<64).map { UInt8($0) })
        let ref = try store.attachFirmwareReport(report, originalData: bytes, to: rec.id)
        XCTAssertEqual(ref.archiveStatus, "ok")
        XCTAssertNotNil(ref.archivedBinaryFileName)
        XCTAssertEqual(store.record(id: rec.id)?.kind, .combined)
        XCTAssertEqual(store.record(id: rec.id)?.firmwareRefs.count, 1)

        // Same SHA → update, no duplicate file entry
        let report2 = makeReport(id: "rep-a2", fileName: "unit.bin", sha: String(repeating: "a", count: 64))
        _ = try store.attachFirmwareReport(report2, originalData: bytes, to: rec.id)
        XCTAssertEqual(store.record(id: rec.id)?.firmwareRefs.count, 1)

        // Second distinct firmware
        let reportB = makeReport(id: "rep-b", fileName: "unit-b.bin", sha: String(repeating: "b", count: 64))
        let bytesB = Data(repeating: 7, count: 32)
        _ = try store.attachFirmwareReport(reportB, originalData: bytesB, to: rec.id)
        XCTAssertEqual(store.record(id: rec.id)?.firmwareRefs.count, 2)

        // Reload from disk (flush debounced save first)
        store.flush()
        let reloaded = InvestigationStore(testRoot: tempRoot)
        let again = try XCTUnwrap(reloaded.record(id: rec.id))
        XCTAssertEqual(again.firmwareRefs.count, 2)
        XCTAssertEqual(again.readout?.serial, "UNIT-SN")
        let first = again.firmwareRefs[0]
        let archived = reloaded.loadArchivedFirmwareData(ref: first, investigationId: rec.id)
        XCTAssertEqual(archived, bytes)
        XCTAssertEqual(FirmwareDigest.sha256Hex(archived!), FirmwareDigest.sha256Hex(bytes))
        XCTAssertNotNil(reloaded.loadFirmwareReport(ref: first, investigationId: rec.id))
    }

    func testIdentityConflictPreventsSilentMerge() {
        let rec = store.create(title: "ID", progress: .selectScooter)
        _ = store.attachReadout(makeSummary(serial: "AAA", ble: UUID()), to: rec.id)
        let outcome = store.attachReadout(makeSummary(serial: "BBB", ble: UUID()), to: rec.id)
        guard case .conflict = outcome else {
            return XCTFail("Expected conflict")
        }
        XCTAssertEqual(store.record(id: rec.id)?.readout?.serial, "AAA")

        store.replaceReadout(makeSummary(serial: "BBB"), to: rec.id)
        XCTAssertEqual(store.record(id: rec.id)?.readout?.serial, "BBB")
        XCTAssertEqual(store.record(id: rec.id)?.comparisonStale, true)
    }

    func testProgressDoesNotFallBehindArtifacts() {
        let rec = store.create(title: "P", progress: .selectScooter)
        _ = store.attachReadout(makeSummary(serial: "S1"), to: rec.id)
        // Scooter-only ohne Combined-Warteschritt → abgeschlossen.
        XCTAssertEqual(store.record(id: rec.id)?.reconciledProgress, .showResults)
        store.setProgress(.selectFirmware, for: rec.id)
        XCTAssertEqual(store.record(id: rec.id)?.reconciledProgress, .selectFirmware)
        XCTAssertTrue(store.record(id: rec.id)?.isResumable == true)
    }

    func testCorruptIndexDoesNotWipeSilently() throws {
        let rec = store.create(title: "Keep", progress: .selectScooter)
        _ = store.attachReadout(makeSummary(serial: "KEEP"), to: rec.id)
        store.flush()
        let index = tempRoot.appendingPathComponent("index.json")
        try Data("{not-json".utf8).write(to: index, options: .atomic)
        let broken = InvestigationStore(testRoot: tempRoot)
        XCTAssertNotNil(broken.lastLoadError)
        // Raw backup should exist
        let backups = try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
        XCTAssertTrue(backups.contains { $0.lastPathComponent.contains("corrupt") })
    }

    func testExportJSONContainsSources() throws {
        let rec = store.create(title: "JSON", progress: .selectScooter)
        _ = store.attachReadout(makeSummary(serial: "J1"), to: rec.id)
        let report = makeReport(id: "jrep", fileName: "j.bin", sha: String(repeating: "c", count: 64))
        _ = try store.attachFirmwareReport(report, originalData: Data([1, 2, 3]), to: rec.id)
        let data = try store.exportJSON(for: rec.id)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["investigationId"] as? String, rec.id)
        XCTAssertNotNil(obj["sourceVersions"])
        XCTAssertNotNil(obj["firmwareFiles"])
    }

    // MARK: - Helpers

    private func makeSummary(serial: String, ble: UUID? = nil) -> InvestigationReadoutSummary {
        InvestigationReadoutSummary(
            id: UUID().uuidString,
            savedAt: Date(),
            protocolNumber: nil,
            profileId: "zt3ProD",
            modelLabel: "ZT3 Pro D",
            manufacturer: "Segway-Ninebot",
            serial: serial,
            fwVcu: "1.5.5",
            fwMcu: "1.5.2",
            fwBle: "2.1.13",
            fwEsc: nil,
            hardwareVersion: nil,
            controllerHint: nil,
            bleAdvertisementName: "NBZing",
            speedLimitKmh: 25,
            blePeripheralId: ble,
            historyEntryId: nil
        )
    }

    private func makeRef(name: String, sha: String, reportId: String) -> InvestigationFirmwareRef {
        InvestigationFirmwareRef(
            id: UUID().uuidString,
            addedAt: Date(),
            analyzedAt: Date(),
            originalFileName: name,
            subjectSHA256: sha,
            byteCount: 10,
            containerKind: "bareBinary",
            reportId: reportId,
            reportFileName: "firmware-\(reportId).json",
            archivedBinaryFileName: nil,
            archiveStatus: "missing",
            archiveError: nil,
            serverJobId: nil,
            analysisCompleteness: nil,
            packageDisplayName: nil,
            referenceTrust: nil
        )
    }

    private func makeReport(id: String, fileName: String, sha: String) -> FirmwareForensicReport {
        let digest = FirmwareFileDigest(
            md5: "d41d8cd98f00b204e9800998ecf8427e",
            sha256: sha,
            byteCount: 64,
            shannonEntropy: 4.0
        )
        return FirmwareForensicReport(
            id: id,
            analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalFileName: fileName,
            containerKind: .bareBinary,
            archiveByteCount: 64,
            archiveDigest: digest,
            meta: FirmwarePackageMeta(
                schemaVersion: 1,
                displayName: "Unit",
                models: ["zt3"],
                type: "VCU",
                compatible: [],
                declaredMd5: nil,
                declaredEncrypted: false,
                rawInfoJSON: nil
            ),
            entries: [],
            primaryFirmwarePath: fileName,
            crypto: FirmwareCryptoAssessment(
                status: .plaintext,
                detectedFormat: "bin",
                decryptionAvailable: false,
                decryptionNote: "",
                evidence: []
            ),
            binary: FirmwareBinaryAnalysis(
                performed: true,
                unavailableReason: nil,
                architecture: .armCortexMLikely,
                vectorTableLikely: true,
                resetHandlerHint: nil,
                stringsSample: [],
                codeDataNotes: []
            ),
            evidence: [],
            comparison: nil,
            verdict: .gray,
            verdictRationale: "unit",
            limits: [],
            vehicleContext: nil,
            vehicleLinkNotes: [],
            summary: "unit",
            deepAnalysis: nil,
            serverArtifacts: FirmwareServerArtifacts(jobId: "job-\(id)")
        )
    }
}
