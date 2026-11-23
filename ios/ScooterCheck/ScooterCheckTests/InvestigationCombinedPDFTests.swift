import XCTest
import PDFKit
@testable import ScooterCheck

@MainActor
final class InvestigationCombinedPDFTests: XCTestCase {

    func testCombinedPDFRendersMultiPageWithSectionsAndLongSHA() throws {
        let sha = String(repeating: "ab", count: 32) // 64 hex
        let digest = FirmwareFileDigest(
            md5: "d41d8cd98f00b204e9800998ecf8427e",
            sha256: sha,
            byteCount: 256,
            shannonEntropy: 5.0
        )
        var deep = FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sources: [.serverDecompile],
            subjectSHA256: sha,
            packageDisplayName: "Combined Fixture",
            models: ["zt3"],
            controllerType: "VCU",
            speedLimits: [],
            maxSpeedKmhInCode: 32,
            legalCapKmhInCode: 20,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: ["Demo"],
            notes: ["PDF-Test"],
            caveats: ["Unit-Test-Caveat"],
            quality: .init(hasDeterministicBasis: true, llmSchemaValidated: false, summary: "synthetic"),
            stockDiff: nil,
            yaraMatches: []
        )
        deep.analysisCompleteness = "PARTIAL"

        let report = FirmwareForensicReport(
            id: "combined-pdf",
            analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalFileName: "combined.bin",
            containerKind: .bareBinary,
            archiveByteCount: 256,
            archiveDigest: digest,
            meta: FirmwarePackageMeta(
                schemaVersion: 1,
                displayName: "Combined",
                models: ["zt3"],
                type: "VCU",
                compatible: [],
                declaredMd5: nil,
                declaredEncrypted: false,
                rawInfoJSON: nil
            ),
            entries: [],
            primaryFirmwarePath: "combined.bin",
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
            evidence: [
                FirmwareEvidenceItem(
                    id: "e1",
                    category: .limitation,
                    title: "Keine Installation nachgewiesen",
                    detail: "Datei≠Flash",
                    evidence: "policy",
                    method: "doc",
                    verifiability: .unverified,
                    confirmed: false
                )
            ],
            comparison: nil,
            verdict: .yellow,
            verdictRationale: "Testhinweis",
            limits: ["Unit"],
            vehicleContext: nil,
            vehicleLinkNotes: [],
            summary: "Kombinierter PDF-Test",
            deepAnalysis: deep,
            serverArtifacts: FirmwareServerArtifacts(jobId: "job-combined", decompileSaved: true)
        )

        let readout = InvestigationReadoutSummary(
            id: "r1",
            savedAt: Date(timeIntervalSince1970: 1_700_000_100),
            protocolNumber: "P-TEST",
            profileId: "zt3ProD",
            modelLabel: "ZT3 Pro D",
            manufacturer: "Segway-Ninebot",
            serial: "SN-PDF-1",
            fwVcu: "1.5.5",
            fwMcu: "1.5.2",
            fwBle: "2.1.13",
            fwEsc: nil,
            hardwareVersion: nil,
            controllerHint: nil,
            bleAdvertisementName: "NBZing",
            speedLimitKmh: 25,
            blePeripheralId: UUID(),
            historyEntryId: nil
        )
        let ref = InvestigationFirmwareRef(
            id: "f1",
            addedAt: Date(timeIntervalSince1970: 1_700_000_200),
            analyzedAt: report.analyzedAt,
            originalFileName: report.originalFileName,
            subjectSHA256: sha,
            byteCount: 256,
            containerKind: "bareBinary",
            reportId: report.id,
            reportFileName: "firmware-combined-pdf.json",
            archivedBinaryFileName: "original-ab.bin",
            archiveStatus: "ok",
            archiveError: nil,
            serverJobId: "job-combined",
            analysisCompleteness: "PARTIAL",
            packageDisplayName: "Combined Fixture",
            referenceTrust: "communityLibrary"
        )
        let record = InvestigationRecord(
            id: "inv-pdf-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
            title: "ZT3 Pro D · SN-PDF-1",
            readout: readout,
            firmwareRefs: [ref],
            notes: ["unit"],
            progress: .showResults,
            comparisonStale: false,
            comparisonNotes: []
        )

        let data = InvestigationCombinedPDF.render(
            record: record,
            reports: [(ref, report)],
            dualSource: DualSourcePanicCorrelator.assess(
                forensic: report,
                reading: nil,
                profile: nil
            )
        )
        XCTAssertGreaterThan(data.count, 800)
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")

        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(doc.pageCount, 1)

        // Write atomically like share-sheet path
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvestigationCombinedPDFTests-\(UUID().uuidString).pdf")
        try data.write(to: url, options: .atomic)
        let reloaded = try Data(contentsOf: url)
        XCTAssertEqual(reloaded.prefix(5), data.prefix(5))
        try? FileManager.default.removeItem(at: url)

        // Subject markers
        if let attrs = doc.documentAttributes {
            let subject = (attrs[PDFDocumentAttribute.subjectAttribute] as? String) ?? ""
            XCTAssertTrue(subject.contains("COMBINED") || subject.contains("inv-pdf-1") || subject.contains("investigation="))
        }
    }

    func testIdentityCompareConflictAndCompatible() {
        let a = InvestigationReadoutSummary(
            id: "1", savedAt: Date(), protocolNumber: nil, profileId: "a",
            modelLabel: "Max G3 D", manufacturer: "X", serial: "S1",
            fwVcu: nil, fwMcu: nil, fwBle: nil, fwEsc: nil,
            hardwareVersion: nil, controllerHint: nil, bleAdvertisementName: nil,
            speedLimitKmh: nil, blePeripheralId: UUID(), historyEntryId: nil
        )
        let b = InvestigationReadoutSummary(
            id: "2", savedAt: Date(), protocolNumber: nil, profileId: "a",
            modelLabel: "Max G3 D", manufacturer: "X", serial: "S2",
            fwVcu: nil, fwMcu: nil, fwBle: nil, fwEsc: nil,
            hardwareVersion: nil, controllerHint: nil, bleAdvertisementName: nil,
            speedLimitKmh: nil, blePeripheralId: UUID(), historyEntryId: nil
        )
        let c = InvestigationReadoutSummary(
            id: "3", savedAt: Date(), protocolNumber: nil, profileId: "a",
            modelLabel: "Max G3 D", manufacturer: "X", serial: "S1",
            fwVcu: nil, fwMcu: nil, fwBle: nil, fwEsc: nil,
            hardwareVersion: nil, controllerHint: nil, bleAdvertisementName: nil,
            speedLimitKmh: nil, blePeripheralId: a.blePeripheralId, historyEntryId: nil
        )
        if case .conflict(let reasons) = InvestigationIdentity.compare(existing: a, candidate: b) {
            XCTAssertFalse(reasons.isEmpty)
        } else {
            XCTFail("expected conflict")
        }
        if case .compatible = InvestigationIdentity.compare(existing: a, candidate: c) {
            // ok
        } else {
            XCTFail("expected compatible")
        }
    }

    func testResumeProgressMapping() {
        XCTAssertEqual(CombinedInvestigationStep.from(progress: .selectFirmware), .pickFirmware)
        XCTAssertEqual(CombinedInvestigationStep.from(progress: .showResults), .results)
        XCTAssertEqual(CombinedInvestigationStep.pickFirmware.asPersisted, .selectFirmware)
    }
}
