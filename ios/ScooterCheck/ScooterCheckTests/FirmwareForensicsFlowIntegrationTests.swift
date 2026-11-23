import XCTest
@testable import ScooterCheck

/// Cycle-9 offline integration: pick → local integrity → status/crypto gate → save wiring.
/// Live iOS↔service E2E is NOT RUN here (no API secrets on this agent image).
@MainActor
final class FirmwareForensicsFlowIntegrationTests: XCTestCase {

    private var tempRoot: URL!
    private var store: InvestigationStore!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FwFlowInt-\(UUID().uuidString)", isDirectory: true)
        store = InvestigationStore(testRoot: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        store = nil
        tempRoot = nil
        super.tearDown()
    }

    // MARK: - Status mapping (resolve + job fixtures)

    func testResolveQueuedJobMapsToQueuedToken() {
        let crypto = plaintextCrypto()
        let job = makeJob(state: .queued, plaintext: false, decompile: false)
        let status = FirmwareAnalysisJobUIStatusMapper.resolve(job: job, crypto: crypto)
        XCTAssertEqual(status.token, "QUEUED")
        XCTAssertFalse(status.allowsSuccessfulDecompileClaim)
    }

    func testResolveProcessingStatesMapToProcessing() {
        let crypto = plaintextCrypto()
        for state: FirmwareAnalysisJobState in [.decrypting, .decompiling, .extracting, .llmEnrichment] {
            let job = makeJob(state: state, plaintext: false, decompile: false)
            XCTAssertEqual(
                FirmwareAnalysisJobUIStatusMapper.resolve(job: job, crypto: crypto).token,
                "PROCESSING",
                "\(state)"
            )
        }
    }

    func testResolveFailedJobMapsToFailed() {
        let job = makeJob(state: .failed, plaintext: false, decompile: false, errorCode: "DECRYPT_FAILED")
        let status = FirmwareAnalysisJobUIStatusMapper.resolve(job: job, crypto: encryptedCrypto())
        XCTAssertEqual(status.token, "FAILED")
    }

    func testResolveCompletedEncryptedWithoutPlaintextIsIncomplete() {
        let job = makeJob(state: .completed, plaintext: false, decompile: false)
        let status = FirmwareAnalysisJobUIStatusMapper.resolve(job: job, crypto: encryptedCrypto())
        XCTAssertEqual(status.token, "INCOMPLETE")
        XCTAssertFalse(status.allowsSuccessfulDecompileClaim)
    }

    func testResolveCompletedEncryptedWithPlaintextNoDecompileIsIncomplete() {
        let job = makeJob(state: .completed, plaintext: true, decompile: false)
        let status = FirmwareAnalysisJobUIStatusMapper.resolve(job: job, crypto: encryptedCrypto())
        XCTAssertEqual(status.token, "INCOMPLETE")
    }

    func testResolveCompletedEncryptedWithPlaintextAndDecompileIsCompleted() {
        let result = makeDeepResult(
            sources: [.serverDecompile],
            completeness: "COMPLETE",
            sha: String(repeating: "d", count: 64)
        )
        let job = makeJob(
            state: .completed,
            plaintext: true,
            decompile: true,
            result: result
        )
        let status = FirmwareAnalysisJobUIStatusMapper.resolve(job: job, crypto: encryptedCrypto())
        XCTAssertEqual(status.token, "COMPLETED")
        XCTAssertTrue(status.allowsSuccessfulDecompileClaim)
    }

    func testResolveCompletenessHintEncryptedOverridesCompleted() {
        let result = makeDeepResult(
            sources: [.localDeterministic],
            completeness: "INCOMPLETE_ENCRYPTED",
            sha: String(repeating: "e", count: 64)
        )
        // Even with plaintext crypto assessment, completeness hint wins on completed.
        let job = makeJob(state: .completed, plaintext: false, decompile: false, result: result)
        let status = FirmwareAnalysisJobUIStatusMapper.resolve(job: job, crypto: plaintextCrypto())
        XCTAssertEqual(status.token, "INCOMPLETE")
    }

    // MARK: - Local pipeline digests + encrypted → INCOMPLETE

    func testLocalPipelineDigestsMatchFirmwareDigestHelper() {
        let payload = Data((0..<128).map { UInt8($0 & 0xFF) })
        let expected = FirmwareDigest.make(from: payload)
        let outcome = FirmwareLocalAnalysisPipeline.analyze(
            fileName: "DRV.bin",
            data: payload
        )
        XCTAssertEqual(outcome.report.archiveDigest.sha256, expected.sha256)
        XCTAssertEqual(outcome.report.archiveDigest.md5, expected.md5)
        XCTAssertEqual(outcome.report.archiveByteCount, 128)
        XCTAssertFalse(outcome.report.archiveDigest.sha256.isEmpty)
        XCTAssertFalse(outcome.report.archiveDigest.md5.isEmpty)
    }

    func testLocalPipelineEncryptedFilenameProducesIncompleteNotCompleted() {
        let payload = Data(repeating: 0xC3, count: 96)
        let outcome = FirmwareLocalAnalysisPipeline.analyze(
            fileName: "FIRM.bin.enc",
            data: payload
        )
        XCTAssertEqual(outcome.report.crypto.status, .confirmedByMetadata)
        XCTAssertEqual(outcome.uiStatus.token, "INCOMPLETE")
        XCTAssertFalse(outcome.uiStatus.allowsSuccessfulDecompileClaim)
        XCTAssertEqual(
            outcome.report.deepAnalysis?.analysisCompleteness,
            "INCOMPLETE_ENCRYPTED_LOCAL"
        )
        XCTAssertFalse(outcome.report.binary.performed)
    }

    func testLocalPipelinePlaintextAllowsCompletedClaim() {
        // Low-entropy repeating payload tends toward plaintext / analyzable path.
        let payload = Data(repeating: 0x00, count: 256) + Data("Ninebot".utf8)
        let outcome = FirmwareLocalAnalysisPipeline.analyze(
            fileName: "FIRM.bin",
            data: payload
        )
        // Crypto may be plaintext or unknownFormat depending on heuristics; gate must not
        // claim COMPLETED decompile for encrypted.
        if outcome.report.crypto.status == .confirmedByMetadata
            || outcome.report.crypto.status == .likelyByStructure {
            XCTAssertEqual(outcome.uiStatus.token, "INCOMPLETE")
        } else if outcome.report.crypto.status == .unknownFormat {
            XCTAssertEqual(outcome.uiStatus.token, "UNSUPPORTED")
        } else {
            XCTAssertEqual(outcome.uiStatus.token, "COMPLETED")
            XCTAssertTrue(outcome.uiStatus.allowsSuccessfulDecompileClaim)
        }
    }

    // MARK: - attachFirmwareReport wiring helpers

    func testAttachHelperCreatesInvestigationWhenActiveMissing() throws {
        var activeId: String? = nil
        let outcome = FirmwareLocalAnalysisPipeline.analyze(
            fileName: "unit.bin",
            data: Data((0..<48).map { UInt8($0) })
        )
        let attach = FirmwareInvestigationAttach.attach(
            report: outcome.report,
            originalData: Data((0..<48).map { UInt8($0) }),
            store: store,
            activeInvestigationId: &activeId
        )
        XCTAssertTrue(attach.didAttach)
        XCTAssertTrue(attach.createdNewInvestigation)
        XCTAssertEqual(activeId, attach.investigationId)
        let rec = try XCTUnwrap(store.record(id: attach.investigationId))
        XCTAssertEqual(rec.kind, .firmwareOnly)
        XCTAssertEqual(rec.firmwareRefs.count, 1)
        XCTAssertEqual(rec.firmwareRefs[0].archiveStatus, "ok")
        XCTAssertEqual(attach.ref?.subjectSHA256, outcome.report.archiveDigest.sha256)
    }

    func testAttachHelperReusesActiveInvestigation() throws {
        let existing = store.create(title: "Vorhanden", progress: .analyzeFirmware)
        var activeId: String? = existing.id
        let payload = Data(repeating: 9, count: 40)
        let outcome = FirmwareLocalAnalysisPipeline.analyze(fileName: "reuse.bin", data: payload)
        let attach = FirmwareInvestigationAttach.attach(
            report: outcome.report,
            originalData: payload,
            store: store,
            activeInvestigationId: &activeId
        )
        XCTAssertTrue(attach.didAttach)
        XCTAssertFalse(attach.createdNewInvestigation)
        XCTAssertEqual(attach.investigationId, existing.id)
        XCTAssertEqual(store.records.filter { $0.id == existing.id }.count, 1)
        XCTAssertEqual(store.record(id: existing.id)?.firmwareRefs.count, 1)
    }

    func testAttachHelperStaleActiveIdCreatesNew() throws {
        var activeId: String? = "missing-id-\(UUID().uuidString)"
        let payload = Data([1, 2, 3, 4, 5])
        let outcome = FirmwareLocalAnalysisPipeline.analyze(fileName: "stale.bin", data: payload)
        let attach = FirmwareInvestigationAttach.attach(
            report: outcome.report,
            originalData: payload,
            store: store,
            activeInvestigationId: &activeId
        )
        XCTAssertTrue(attach.didAttach)
        XCTAssertTrue(attach.createdNewInvestigation)
        XCTAssertNotEqual(attach.investigationId, "missing-id")
        XCTAssertEqual(activeId, attach.investigationId)
    }

    func testOfflineFlowPickAnalyzeGateAttachRoundTrip() throws {
        // Simulates Hub save path without UI: local analyze → crypto gate → attach → reload.
        let bytes = Data((0..<64).map { UInt8(255 &- $0) })
        let fileName = "FIRM.bin.enc"
        let analyzed = FirmwareLocalAnalysisPipeline.analyze(fileName: fileName, data: bytes)
        XCTAssertEqual(analyzed.uiStatus.token, "INCOMPLETE")

        var activeId: String? = nil
        let attach = FirmwareInvestigationAttach.attach(
            report: analyzed.report,
            originalData: bytes,
            store: store,
            activeInvestigationId: &activeId
        )
        XCTAssertTrue(attach.didAttach)
        store.flush()

        let reloaded = InvestigationStore(testRoot: tempRoot)
        let rec = try XCTUnwrap(reloaded.record(id: attach.investigationId))
        XCTAssertEqual(rec.firmwareRefs.count, 1)
        let ref = rec.firmwareRefs[0]
        XCTAssertEqual(ref.originalFileName, fileName)
        let archived = try XCTUnwrap(
            reloaded.loadArchivedFirmwareData(ref: ref, investigationId: rec.id)
        )
        XCTAssertEqual(archived, bytes)
        XCTAssertEqual(FirmwareDigest.sha256Hex(archived), analyzed.report.archiveDigest.sha256)

        let loadedReport = try XCTUnwrap(
            reloaded.loadFirmwareReport(ref: ref, investigationId: rec.id)
        )
        XCTAssertEqual(loadedReport.crypto.status, .confirmedByMetadata)
        // Re-apply crypto gate on persisted report — still INCOMPLETE, never COMPLETED claim.
        let ui = FirmwareAnalysisJobUIStatusMapper.resolve(
            job: nil,
            crypto: loadedReport.crypto,
            localOnlyFallback: .completed
        )
        XCTAssertEqual(ui.token, "INCOMPLETE")
        XCTAssertFalse(ui.allowsSuccessfulDecompileClaim)
    }

    func testMergingServerCompletedWithoutPlaintextKeepsHonestLimits() {
        let local = FirmwareLocalAnalysisPipeline.analyze(
            fileName: "FIRM.bin.enc",
            data: Data(repeating: 0x11, count: 32)
        )
        let job = makeJob(state: .completed, plaintext: false, decompile: false)
        let merged = FirmwareLocalAnalysisPipeline.mergingServerResult(into: local.report, job: job)
        XCTAssertEqual(merged.serverArtifacts?.jobId, job.jobId)
        XCTAssertTrue(
            merged.limits.contains {
                $0.localizedCaseInsensitiveContains("ohne Klartext")
                    || $0.localizedCaseInsensitiveContains("kein erfolgreiches Decompile")
            }
        )
        let ui = FirmwareAnalysisJobUIStatusMapper.resolve(job: job, crypto: merged.crypto)
        XCTAssertEqual(ui.token, "INCOMPLETE")
    }

    // MARK: - CrossSourceCorrelator no-regression smoke (untouched API)

    func testCrossSourceCorrelatorStillConfirmsMatchingFirmware() {
        let snapshot = CrossSourceSnapshot(
            bleDevice: nil,
            firmwareVersions: CorrelationFirmwareVersions(fwVcu: "1.5.8"),
            deviceTraits: nil,
            zipMeta: CorrelationZipMeta(
                fileName: "DRV_1.5.8_G3.zip",
                displayName: "Max G3 DRV 1.5.8",
                models: ["G3"],
                compatibleBoards: [],
                computedMd5: nil,
                declaredMd5: nil,
                md5Matches: nil,
                firmSizeBytes: nil,
                findings: []
            ),
            forensicStub: nil
        )
        let result = CrossSourceCorrelator.assess(snapshot)
        XCTAssertTrue(result.confirmedItems.contains { $0.kind == .firmwareVersion })
    }

    // MARK: - Helpers

    private func plaintextCrypto() -> FirmwareCryptoAssessment {
        FirmwareCryptoAssessment(
            status: .plaintext,
            detectedFormat: "bin",
            decryptionAvailable: false,
            decryptionNote: "n/a",
            evidence: []
        )
    }

    private func encryptedCrypto() -> FirmwareCryptoAssessment {
        FirmwareCryptoAssessment(
            status: .confirmedByMetadata,
            detectedFormat: "enc",
            decryptionAvailable: false,
            decryptionNote: "offline",
            evidence: ["encrypted=true"]
        )
    }

    private func makeDeepResult(
        sources: [FirmwareDeepAnalysisSource],
        completeness: String?,
        sha: String
    ) -> FirmwareDeepAnalysisResult {
        FirmwareDeepAnalysisResult(
            schemaVersion: FirmwareDeepAnalysisResult.currentSchemaVersion,
            producedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sources: sources,
            subjectSHA256: sha,
            models: [],
            speedLimits: [],
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: [],
            caveats: [],
            quality: .init(
                hasDeterministicBasis: true,
                llmSchemaValidated: false,
                summary: "fixture"
            ),
            analysisCompleteness: completeness
        )
    }

    private func makeJob(
        state: FirmwareAnalysisJobState,
        plaintext: Bool,
        decompile: Bool,
        errorCode: String? = nil,
        result: FirmwareDeepAnalysisResult? = nil
    ) -> FirmwareAnalysisJobStatus {
        FirmwareAnalysisJobStatus(
            jobId: "job-\(UUID().uuidString.prefix(8))",
            state: state,
            progressPercent: state == .completed ? 100 : 40,
            message: state.rawValue,
            result: result,
            errorCode: errorCode,
            plaintextPath: plaintext ? "/tmp/plain.bin" : nil,
            plaintextSHA256: plaintext ? String(repeating: "a", count: 64) : nil,
            plaintextSaved: plaintext,
            decompilePath: decompile ? "/tmp/decomp.c" : nil,
            decompileSaved: decompile
        )
    }
}
