import XCTest
@testable import ScooterCheck

final class FirmwareAnalysisJobUIStatusTests: XCTestCase {

    // MARK: - Wire state → UI tokens

    func testQueuedMapsToQueued() {
        XCTAssertEqual(
            FirmwareAnalysisJobUIStatusMapper.fromJobState(.queued).token,
            "QUEUED"
        )
    }

    func testProcessingStatesMapToProcessing() {
        let states: [FirmwareAnalysisJobState] = [
            .decrypting, .decompiling, .extracting, .llmEnrichment
        ]
        for state in states {
            XCTAssertEqual(
                FirmwareAnalysisJobUIStatusMapper.fromJobState(state).token,
                "PROCESSING",
                "\(state) should map to PROCESSING"
            )
        }
    }

    func testCompletedAndFailedWireMapping() {
        XCTAssertEqual(
            FirmwareAnalysisJobUIStatusMapper.fromJobState(.completed).token,
            "COMPLETED"
        )
        XCTAssertEqual(
            FirmwareAnalysisJobUIStatusMapper.fromJobState(.failed).token,
            "FAILED"
        )
        XCTAssertEqual(
            FirmwareAnalysisJobUIStatusMapper.fromJobState(.notConfigured).token,
            "FAILED"
        )
    }

    // MARK: - Crypto gate

    func testEncryptedWithoutPlaintextIsIncompleteNotCompleted() {
        let crypto = FirmwareCryptoAssessment(
            status: .confirmedByMetadata,
            detectedFormat: "enc",
            decryptionAvailable: false,
            decryptionNote: "offline",
            evidence: ["encrypted=true"]
        )
        let status = FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
            base: .completed,
            crypto: crypto,
            serverPlaintextAvailable: false,
            serverDecompileAvailable: false
        )
        XCTAssertEqual(status.token, "INCOMPLETE")
        XCTAssertFalse(status.allowsSuccessfulDecompileClaim)
    }

    func testLikelyEncryptedWithoutPlaintextIsIncomplete() {
        let crypto = FirmwareCryptoAssessment(
            status: .likelyByStructure,
            detectedFormat: "high entropy",
            decryptionAvailable: false,
            decryptionNote: "offline",
            evidence: []
        )
        let status = FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
            base: .completed,
            crypto: crypto,
            serverPlaintextAvailable: false,
            serverDecompileAvailable: true
        )
        XCTAssertEqual(status.token, "INCOMPLETE")
    }

    func testUnknownFormatWithoutArtifactsIsUnsupported() {
        let crypto = FirmwareCryptoAssessment(
            status: .unknownFormat,
            detectedFormat: "?",
            decryptionAvailable: false,
            decryptionNote: "n/a",
            evidence: []
        )
        let status = FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
            base: .completed,
            crypto: crypto,
            serverPlaintextAvailable: false,
            serverDecompileAvailable: false
        )
        XCTAssertEqual(status.token, "UNSUPPORTED")
        XCTAssertFalse(status.allowsSuccessfulDecompileClaim)
    }

    func testPlaintextCompletedStaysCompleted() {
        let crypto = FirmwareCryptoAssessment(
            status: .plaintext,
            detectedFormat: "plain",
            decryptionAvailable: false,
            decryptionNote: "n/a",
            evidence: []
        )
        let status = FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
            base: .completed,
            crypto: crypto,
            serverPlaintextAvailable: false,
            serverDecompileAvailable: false
        )
        XCTAssertEqual(status.token, "COMPLETED")
        XCTAssertTrue(status.allowsSuccessfulDecompileClaim)
    }

    func testEncryptedWithPlaintextAndDecompileIsCompleted() {
        let crypto = FirmwareCryptoAssessment(
            status: .confirmedByMetadata,
            detectedFormat: "enc",
            decryptionAvailable: false,
            decryptionNote: "offline",
            evidence: []
        )
        let status = FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
            base: .completed,
            crypto: crypto,
            serverPlaintextAvailable: true,
            serverDecompileAvailable: true
        )
        XCTAssertEqual(status.token, "COMPLETED")
    }

    func testEncryptedWithPlaintextButNoDecompileIsIncomplete() {
        let crypto = FirmwareCryptoAssessment(
            status: .confirmedByMetadata,
            detectedFormat: "enc",
            decryptionAvailable: false,
            decryptionNote: "offline",
            evidence: []
        )
        let status = FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
            base: .completed,
            crypto: crypto,
            serverPlaintextAvailable: true,
            serverDecompileAvailable: false
        )
        XCTAssertEqual(status.token, "INCOMPLETE")
    }

    func testInFlightStatesIgnoreCryptoGate() {
        let crypto = FirmwareCryptoAssessment(
            status: .confirmedByMetadata,
            detectedFormat: "enc",
            decryptionAvailable: false,
            decryptionNote: "offline",
            evidence: []
        )
        XCTAssertEqual(
            FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
                base: .queued,
                crypto: crypto,
                serverPlaintextAvailable: false,
                serverDecompileAvailable: false
            ).token,
            "QUEUED"
        )
        XCTAssertEqual(
            FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
                base: .processing,
                crypto: crypto,
                serverPlaintextAvailable: false,
                serverDecompileAvailable: false
            ).token,
            "PROCESSING"
        )
    }

    func testCompletenessHintOverridesCompleted() {
        let crypto = FirmwareCryptoAssessment(
            status: .plaintext,
            detectedFormat: "plain",
            decryptionAvailable: false,
            decryptionNote: "n/a",
            evidence: []
        )
        let status = FirmwareAnalysisJobUIStatusMapper.applyCryptoGate(
            base: .completed,
            crypto: crypto,
            serverPlaintextAvailable: false,
            serverDecompileAvailable: false,
            completenessHint: "ENCRYPTED_UNSUPPORTED"
        )
        XCTAssertEqual(status.token, "UNSUPPORTED")
    }

    // MARK: - Local pipeline crypto gate

    func testLocalPipelineEncryptedProducesIncompleteUIStatus() {
        let payload = Data(repeating: 0xAB, count: 64)
        let outcome = FirmwareLocalAnalysisPipeline.analyze(
            fileName: "FIRM.bin.enc",
            data: payload
        )
        XCTAssertEqual(outcome.report.crypto.status, .confirmedByMetadata)
        XCTAssertEqual(outcome.uiStatus.token, "INCOMPLETE")
        XCTAssertFalse(outcome.uiStatus.allowsSuccessfulDecompileClaim)
        XCTAssertFalse(outcome.report.binary.performed)
    }

    func testLocalPipelineExposesIntegrityDigests() {
        let payload = Data((0..<32).map { UInt8($0) })
        let outcome = FirmwareLocalAnalysisPipeline.analyze(
            fileName: "FIRM.bin",
            data: payload
        )
        XCTAssertFalse(outcome.report.archiveDigest.sha256.isEmpty)
        XCTAssertFalse(outcome.report.archiveDigest.md5.isEmpty)
        XCTAssertTrue(outcome.report.evidence.contains { $0.id == "pkg-sha256" || $0.id == "pkg-sha256-archive" })
    }

    func testServerClientAcceptsAPITokenWithoutJWT() {
        let client = FirmwareServerAnalysisClient(
            baseURL: URL(string: "https://example.test/fw"),
            apiToken: "settings-token",
            bearerToken: nil,
            clientId: "ios-test"
        )
        XCTAssertTrue(client.isConfigured)
        XCTAssertTrue(client.hasAPIToken)
        XCTAssertFalse(client.hasBearerJWT)
        XCTAssertTrue(client.hasAuthCredential)
    }

    func testServerClientLoginRequiredWithoutAnyCredential() {
        let client = FirmwareServerAnalysisClient(
            baseURL: URL(string: "https://example.test/fw"),
            apiToken: nil,
            bearerToken: nil,
            clientId: "ios-test"
        )
        XCTAssertTrue(client.isConfigured)
        XCTAssertFalse(client.hasAuthCredential)
    }
}
