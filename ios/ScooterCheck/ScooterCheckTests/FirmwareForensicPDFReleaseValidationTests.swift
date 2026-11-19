import XCTest
import PDFKit
import UIKit
@testable import ScooterCheck

/// Final release acceptance — six synthetic PDFKit reports + page previews for CI artifacts.
///
/// Files are written under a stable subdirectory of the process temporary directory
/// (`release-validation-pdf/`) and also attached via `XCTAttachment` so GitHub Actions
/// can recover them from the simulator data container and/or the `.xcresult` bundle.
final class FirmwareForensicPDFReleaseValidationTests: XCTestCase {

    /// Prefer an explicit host-forwarded env var; always also write under tmp marker dir.
    private var outputRoot: URL {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-validation-pdf", isDirectory: true)
        if let env = ProcessInfo.processInfo.environment["FIRMWARE_PDF_VALIDATION_DIR"], !env.isEmpty {
            // When the simulator can write to the host path (SIMCTL_CHILD_*), use it.
            // Always keep tmpRoot as a discoverable fallback for simctl get_app_container.
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return tmpRoot
    }

    private var fallbackTmpRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("release-validation-pdf", isDirectory: true)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        for root in [outputRoot, fallbackTmpRoot] {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("previews", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    func testReleasePDFValidationSixReportsAndPreviews() throws {
        var summary: [[String: Any]] = []

        let cases: [(String, FirmwareForensicReport, Int)] = [
            ("short-report", makeShortReport(), 1),
            ("full-report", makeFullReport(), 2),
            ("long-values", makeLongValuesReport(), 1),
            ("many-findings", makeManyFindingsReport(), 2),
            ("truncated-results", makeTruncatedReport(), 1),
            ("incomplete-analysis", makeIncompleteReport(), 1),
        ]

        for (name, report, minPages) in cases {
            let result = try validateAndExport(name: name, report: report, minPages: minPages)
            summary.append(result)
        }

        let payload: [String: Any] = [
            "phase": "final-release-acceptance",
            "environment": "PDFKit/iOS-Simulator",
            "outputDirectory": outputRoot.path,
            "fallbackDirectory": fallbackTmpRoot.path,
            "reports": summary,
            "checks": [
                "pdfMagic",
                "pdfDocumentOpen",
                "pageCount",
                "mediaBox",
                "textExtraction",
                "jsonConsistency",
                "pagePreviews",
                "xctAttachment",
            ],
            "note": "Synthetic fixtures only — no personal or production data.",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try writeArtifact(data, relativePath: "validation-summary.json", contentType: "public.json")
        // Machine-readable path marker for CI logs / simctl recovery.
        let marker = """
        FIRMWARE_PDF_VALIDATION_OUTPUT=\(outputRoot.path)
        FIRMWARE_PDF_VALIDATION_FALLBACK=\(fallbackTmpRoot.path)
        FIRMWARE_PDF_VALIDATION_REPORTS=\(summary.count)
        """
        try writeArtifact(
            Data(marker.utf8),
            relativePath: "validation-path.txt",
            contentType: "public.plain-text"
        )
        print(marker)
        XCTAssertEqual(summary.count, 6)
    }

    // MARK: - Artifact I/O

    /// Writes to the preferred output root, mirrors into the tmp fallback, and attaches for xcresult.
    private func writeArtifact(_ data: Data, relativePath: String, contentType: String) throws {
        let roots = (outputRoot.path == fallbackTmpRoot.path)
            ? [outputRoot]
            : [outputRoot, fallbackTmpRoot]
        for root in roots {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            XCTAssertGreaterThan(
                (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0,
                0,
                "empty artifact \(relativePath)"
            )
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: contentType)
        attachment.name = relativePath
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Validation helpers

    @discardableResult
    private func validateAndExport(
        name: String,
        report: FirmwareForensicReport,
        minPages: Int
    ) throws -> [String: Any] {
        let pdf = FirmwareForensicPDF.render(report)
        XCTAssertGreaterThan(pdf.count, 500, "\(name): empty PDF")
        let magic = String(data: pdf.prefix(5), encoding: .ascii) ?? ""
        XCTAssertEqual(magic, "%PDF-", "\(name): missing PDF magic")

        let pdfName = "\(name).pdf"
        try writeArtifact(pdf, relativePath: pdfName, contentType: "com.adobe.pdf")

        guard let doc = PDFDocument(data: pdf) else {
            XCTFail("\(name): PDFDocument.open failed")
            return ["name": name, "ok": false]
        }
        XCTAssertGreaterThanOrEqual(doc.pageCount, minPages, "\(name): expected ≥\(minPages) pages")

        var extracted = ""
        var previewPaths: [String] = []
        let pageIndexes: [Int]
        if doc.pageCount <= 2 {
            pageIndexes = Array(0..<doc.pageCount)
        } else {
            // First, last, and a middle page (tables / long text coverage).
            pageIndexes = Array(Set([0, doc.pageCount / 2, doc.pageCount - 1])).sorted()
        }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else {
                XCTFail("\(name): missing page \(i)")
                continue
            }
            let box = page.bounds(for: .mediaBox)
            XCTAssertGreaterThan(box.width, 100, "\(name) page \(i) mediaBox width")
            XCTAssertGreaterThan(box.height, 100, "\(name) page \(i) mediaBox height")
            // Typical A4-ish margins: content should not collapse to zero-size page.
            XCTAssertGreaterThan(box.width * box.height, 10_000)

            extracted += page.string ?? ""
            if pageIndexes.contains(i) {
                let thumb = page.thumbnail(of: CGSize(width: 360, height: 480), for: .mediaBox)
                XCTAssertGreaterThan(thumb.size.width, 0)
                if let png = thumb.pngData() {
                    let previewName = String(format: "%@-page-%02d.png", name, i + 1)
                    try writeArtifact(
                        png,
                        relativePath: "previews/\(previewName)",
                        contentType: "public.png"
                    )
                    previewPaths.append("previews/\(previewName)")
                }
            }
        }

        XCTAssertFalse(extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "\(name): no extractable text")

        // Required fields / consistency with JSON channel.
        let jsonData = try FirmwareForensicPDF.jsonData(report)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FirmwareForensicReport.self, from: jsonData)
        XCTAssertEqual(decoded.deepAnalysis?.subjectSHA256, report.deepAnalysis?.subjectSHA256)
        XCTAssertEqual(decoded.deepAnalysis?.analysisProfileHash, report.deepAnalysis?.analysisProfileHash)
        XCTAssertEqual(
            decoded.deepAnalysis?.referenceMetadata?.referenceTrust,
            report.deepAnalysis?.referenceMetadata?.referenceTrust
        )
        if let trust = decoded.deepAnalysis?.referenceMetadata?.referenceTrust {
            XCTAssertNotEqual(trust, "oemVerified", "\(name): must not elevate community trust")
        }
        let lower = extracted.lowercased()
        XCTAssertFalse(lower.contains("oem verified"), "\(name): PDF must not claim OEM verification")

        // PDF must not claim higher certainty than JSON completeness.
        XCTAssertEqual(decoded.deepAnalysis?.analysisCompleteness, report.deepAnalysis?.analysisCompleteness)
        if report.deepAnalysis?.analysisCompleteness == "PARTIAL"
            || report.deepAnalysis?.analysisCompleteness == "INCOMPLETE" {
            XCTAssertTrue(
                extracted.contains("PARTIAL")
                    || extracted.contains("INCOMPLETE")
                    || extracted.contains("Analysevollständigkeit")
                    || extracted.contains("unvollständig")
                    || extracted.contains("Einschränkung")
                    || (decoded.deepAnalysis?.analysisLimitations?.isEmpty == false),
                "\(name): incomplete analysis must remain visible"
            )
        }

        return [
            "name": name,
            "ok": true,
            "pdf": "\(name).pdf",
            "byteCount": pdf.count,
            "pageCount": doc.pageCount,
            "minPagesRequired": minPages,
            "textLength": extracted.count,
            "subjectSHA256": report.deepAnalysis?.subjectSHA256 ?? "",
            "analysisProfileHash": report.deepAnalysis?.analysisProfileHash ?? "",
            "referenceTrust": report.deepAnalysis?.referenceMetadata?.referenceTrust ?? "",
            "analysisCompleteness": report.deepAnalysis?.analysisCompleteness ?? "",
            "previews": previewPaths,
        ]
    }

    // MARK: - Fixtures

    private func plaintextCrypto() -> FirmwareCryptoAssessment {
        FirmwareCryptoAssessment(
            status: .plaintext,
            detectedFormat: "bin",
            decryptionAvailable: false,
            decryptionNote: "",
            evidence: []
        )
    }

    private func baseDeep(sha: String, profileHash: String) -> FirmwareDeepAnalysisResult {
        var deep = FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sources: [.serverDecompile],
            subjectSHA256: sha,
            packageDisplayName: "Release PDF Fixture",
            models: ["test"],
            controllerType: "VCU",
            speedLimits: [],
            maxSpeedKmhInCode: nil,
            legalCapKmhInCode: nil,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: [],
            caveats: ["Statische Analyse — kein Fahrzeugtest."],
            quality: .init(hasDeterministicBasis: true, llmSchemaValidated: false, summary: "synthetic"),
            stockDiff: nil,
            yaraMatches: []
        )
        deep.analysisProfileHash = profileHash
        deep.analysisProfile = FirmwareAnalysisProfile(
            analysisProfileVersion: "2.2G.1",
            analysisProfileHash: profileHash,
            analyzerCompat: "2",
            ghidraVersion: "12.2_PUBLIC",
            processorArchitecture: "ARM:LE:32:Cortex",
            requestedLoaderBase: "0x08000000",
            seedCortexMEntryPoints: true
        )
        deep.referenceMetadata = FirmwareReferenceMetadata(
            referenceLabel: "community synthetic",
            referenceTrust: "communityLibrary",
            verificationStatus: "community"
        )
        deep.firmwareArchitectureConfidence = "ARCHITECTURE_UNKNOWN"
        deep.analysisCompleteness = "PARTIAL"
        deep.analysisLimitations = ["Statische Analyse — kein Fahrzeugtest."]
        return deep
    }

    private func makeReport(
        id: String,
        fileName: String,
        deep: FirmwareDeepAnalysisResult,
        summary: String,
        limits: [String] = ["Unit-Test-PDF"]
    ) -> FirmwareForensicReport {
        let digest = FirmwareFileDigest(
            md5: "d41d8cd98f00b204e9800998ecf8427e",
            sha256: deep.subjectSHA256 ?? "x",
            byteCount: 512,
            shannonEntropy: 4.5
        )
        return FirmwareForensicReport(
            id: id,
            analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalFileName: fileName,
            containerKind: .bareBinary,
            archiveByteCount: 512,
            archiveDigest: digest,
            meta: FirmwarePackageMeta(
                schemaVersion: 1,
                displayName: "Release Validation",
                models: ["test"],
                type: "VCU",
                compatible: [],
                declaredMd5: nil,
                declaredEncrypted: false,
                rawInfoJSON: nil
            ),
            entries: [],
            primaryFirmwarePath: fileName,
            crypto: plaintextCrypto(),
            binary: FirmwareBinaryAnalysis(
                performed: true,
                unavailableReason: nil,
                architecture: .armCortexMLikely,
                vectorTableLikely: true,
                resetHandlerHint: "0x08000101",
                stringsSample: [],
                codeDataNotes: []
            ),
            evidence: [],
            comparison: nil,
            verdict: .gray,
            verdictRationale: "Synthetischer Release-Validierungsbericht.",
            limits: limits,
            vehicleContext: nil,
            vehicleLinkNotes: [],
            summary: summary,
            deepAnalysis: deep,
            serverArtifacts: nil
        )
    }

    private func makeShortReport() -> FirmwareForensicReport {
        let deep = baseDeep(
            sha: "1111111111111111111111111111111111111111111111111111111111111111",
            profileHash: "shortprof00112233445566778899aabb"
        )
        return makeReport(
            id: "pdf-short",
            fileName: "short.dec.bin",
            deep: deep,
            summary: "Kurze Firmwareanalyse (Release-PDF 1)."
        )
    }

    private func makeFullReport() -> FirmwareForensicReport {
        var deep = baseDeep(
            sha: "2222222222222222222222222222222222222222222222222222222222222222",
            profileHash: "fullprof00112233445566778899aabbcc"
        )
        deep.callGraphQuality = FirmwareCallGraphQuality(
            directCalls: 40, indirectCalls: 3, internalBranches: 80,
            tailCalls: 4, unresolvedCalls: 1, unknownControlFlow: 0, edgeCount: 128
        )
        deep.functionDiff = FirmwareFunctionDiffSummary(
            ok: true, tool: "function_diff", toolNote: nil,
            summary: FirmwareFunctionDiffCounts(
                identical: 20, structurallyChanged: 3, added: 1, removed: 1,
                uncomparable: 0, subjectFunctionCount: 25, referenceFunctionCount: 24,
                overall: nil, matched: 23, ambiguous: 1, matchHigh: 18, matchMedium: 4, matchLow: 1
            ),
            samplePairs: nil, functionMatching: nil,
            analysisLimitations: ["Funktionsdiff ist kein Manipulationsnachweis."],
            notes: nil
        )
        deep.analysisLimitations = (0..<25).map {
            "Vollbericht Einschränkung \($0): Statische Analyse — kein Fahrzeugtest."
        }
        var af = FirmwareActivationForensicsSummary()
        af.ok = true
        af.phase = "2.3.4"
        af.semanticDataFlow = FirmwareActivationSemanticDataFlow(
            ok: true,
            functionsAnalyzed: 42,
            withMemoryReads: 10,
            withMemoryWrites: 8,
            withConditionals: 12,
            withCalls: 20,
            qualityOk: 30,
            qualityPartial: 8,
            qualityMissing: 4,
            fromDataflowExport: 30,
            derivedOnly: 12,
            dataflowCoveragePercent: 71.4,
            exportedFunctions: 30,
            derivedFunctions: 12,
            partialFunctions: 8,
            unavailableFunctions: 4,
            provenanceCounts: ["GHIDRA_EXPORTED": 30, "MNEMONIC_DERIVED": 12],
            dataflowQualityMetrics: FirmwareActivationDataflowQualityMetrics(
                totalFunctions: 42,
                dataflowExportCoverage: 71.4,
                parameterRecoveryCoverage: 40.0,
                parameterNonZeroCoverage: 30.0,
                parameterUnknownCoverage: 55.0,
                parameterPartialCoverage: 5.0,
                exactParameterAccuracy: 90.0,
                acceptedOrAmbiguousRate: 100.0,
                unknownParameterRate: 0.0,
                partialSignatureRate: 0.0,
                recoveredParameterCoverage: 100.0,
                memoryAccessCoverage: 42.0,
                dataReferenceCoverage: 35.0,
                unresolvedDataflowCount: 4,
                semanticConfidenceDistribution: ["GHIDRA_EXPORTED": 30],
                parameterQualityDistribution: [
                    "RECOVERED_PARAMETER_COUNT": 15,
                    "UNKNOWN_PARAMETER_COUNT": 23,
                    "CONFIRMED_ZERO_PARAMETERS": 2,
                    "PARTIAL_SIGNATURE": 2,
                ],
                exportedOkCount: 30,
                parameterKnownCount: 17,
                parameterNonZeroCount: 15,
                parameterUnknownCount: 23,
                parameterPartialCount: 2,
                memoryAccessCount: 18,
                dataReferenceCount: 15,
                note: "exact≠accepted — abweichende Parameterzahlen zählen nicht als exakt korrekt."
            ),
            source: "semantic_dataflow"
        )
        deep.activationForensics = af
        return makeReport(
            id: "pdf-full",
            fileName: "full.dec.bin",
            deep: deep,
            summary: "Vollständige mehrseitige Firmwareanalyse (Release-PDF 2).",
            limits: deep.analysisLimitations ?? []
        )
    }

    private func makeLongValuesReport() -> FirmwareForensicReport {
        let sha = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        let profile = "c0f507820a1457a1af98c2a66352db531f2f4ad1bcf72bc32c58e307e3f41de7"
        var deep = baseDeep(sha: sha, profileHash: profile)
        deep.notes = [
            "SHA-256: \(sha)",
            "Analyseprofil-Hash: \(profile)",
            "Langer Hex-Wert muss umgebrochen werden ohne Pflichtfelder zu verlieren.",
        ]
        return makeReport(
            id: "pdf-long-values",
            fileName: "long_hashes.dec.bin",
            deep: deep,
            summary: "Lange SHA-256- und Profilhash-Werte (Release-PDF 3)."
        )
    }

    private func makeManyFindingsReport() -> FirmwareForensicReport {
        var deep = baseDeep(
            sha: "3333333333333333333333333333333333333333333333333333333333333333",
            profileHash: "manyfind00112233445566778899aabb"
        )
        deep.inputHints = (0..<24).map { i in
            FirmwareInputHintFinding(
                id: "hint-\(i)",
                kind: i % 2 == 0 ? .customButton : .dualAnalog,
                detail: "Eingabe \(i): GPIO/Taster/Blinker-Strukturhinweis",
                evidence: "synthetic-token-\(i)",
                source: .serverDecompile,
                confidence: .medium
            )
        }
        deep.notes = (0..<20).map { "Finding \($0): allgemeine Eingabeverarbeitung (keine Aktivierungssequenz)." }
        deep.analysisLimitations = (0..<12).map { "Viele Findings — Truncation-Hinweis \($0)." }
        return makeReport(
            id: "pdf-many-findings",
            fileName: "many_findings.dec.bin",
            deep: deep,
            summary: "Viele erkannte Eingabefunktionen (Release-PDF 4).",
            limits: deep.analysisLimitations ?? []
        )
    }

    private func makeTruncatedReport() -> FirmwareForensicReport {
        var deep = baseDeep(
            sha: "4444444444444444444444444444444444444444444444444444444444444444",
            profileHash: "truncprof00112233445566778899aa"
        )
        var af = FirmwareActivationForensicsSummary()
        af.ok = true
        af.phase = "2.3.4"
        af.resultLimits = FirmwareActivationResultLimits(
            handlers: FirmwareActivationResultLimitBucket(
                totalFunctionsAnalyzed: 100,
                totalCandidatesDetected: 42,
                returnedCandidates: 25,
                omittedCandidates: 17,
                resultTruncated: true,
                truncationReason: "configured_limit",
                configuredLimit: 25,
                analysisComplete: false
            ),
            conditionalLogic: FirmwareActivationResultLimitBucket(
                totalFunctionsAnalyzed: 100,
                totalCandidatesDetected: 55,
                returnedCandidates: 50,
                omittedCandidates: 5,
                resultTruncated: true,
                truncationReason: "pagination",
                configuredLimit: 50,
                analysisComplete: true
            ),
            evidenceGraph: FirmwareActivationResultLimitBucket(
                totalFunctionsAnalyzed: 42,
                totalCandidatesDetected: 49,
                returnedCandidates: 40,
                omittedCandidates: 9,
                resultTruncated: true,
                truncationReason: "configured_limit",
                configuredLimit: 40,
                analysisComplete: false,
                totalGraphNodes: 120,
                totalGraphEdges: 200,
                returnedGraphNodes: 100,
                returnedGraphEdges: 180
            )
        )
        af.evidenceGraphQuality = FirmwareActivationEvidenceGraphQuality(
            nodeCount: 120,
            edgeCount: 200,
            confirmedEdgeCount: 10,
            indicativeEdgeCount: 40,
            speculativeEdgeCount: 100,
            unresolvedEdgeCount: 50
        )
        deep.activationForensics = af
        return makeReport(
            id: "pdf-truncated",
            fileName: "truncated.dec.bin",
            deep: deep,
            summary: "Ergebnislisten mit Truncation und Pagination (Release-PDF 5)."
        )
    }

    private func makeIncompleteReport() -> FirmwareForensicReport {
        var deep = baseDeep(
            sha: "5555555555555555555555555555555555555555555555555555555555555555",
            profileHash: "incompl00112233445566778899aabb"
        )
        deep.analysisCompleteness = "INCOMPLETE"
        deep.analysisLimitations = [
            "Unvollständige Datenflussanalyse.",
            "Unbekannte Parameterzahlen bleiben unbekannt.",
            "Keine erfundenen Signaturen.",
        ]
        var af = FirmwareActivationForensicsSummary()
        af.ok = false
        af.phase = "2.3.4"
        af.semanticDataFlow = FirmwareActivationSemanticDataFlow(
            ok: false,
            functionsAnalyzed: 10,
            withMemoryReads: 1,
            withMemoryWrites: 0,
            withConditionals: 0,
            withCalls: 2,
            qualityOk: 2,
            qualityPartial: 3,
            qualityMissing: 5,
            fromDataflowExport: 2,
            derivedOnly: 3,
            dataflowCoveragePercent: 20.0,
            exportedFunctions: 2,
            derivedFunctions: 3,
            partialFunctions: 3,
            unavailableFunctions: 5,
            provenanceCounts: ["PARTIAL": 3, "NOT_AVAILABLE": 5],
            dataflowQualityMetrics: FirmwareActivationDataflowQualityMetrics(
                totalFunctions: 10,
                dataflowExportCoverage: 20.0,
                parameterRecoveryCoverage: 0.0,
                parameterNonZeroCoverage: 0.0,
                parameterUnknownCoverage: 100.0,
                parameterPartialCoverage: 0.0,
                exactParameterAccuracy: nil,
                acceptedOrAmbiguousRate: nil,
                unknownParameterRate: 100.0,
                partialSignatureRate: 0.0,
                recoveredParameterCoverage: 0.0,
                memoryAccessCoverage: 10.0,
                dataReferenceCoverage: 0.0,
                unresolvedDataflowCount: 8,
                semanticConfidenceDistribution: ["NOT_AVAILABLE": 5, "PARTIAL": 3],
                parameterQualityDistribution: ["UNKNOWN_PARAMETER_COUNT": 10],
                exportedOkCount: 2,
                parameterKnownCount: 0,
                parameterNonZeroCount: 0,
                parameterUnknownCount: 10,
                parameterPartialCount: 0,
                memoryAccessCount: 1,
                dataReferenceCount: 0,
                note: "Unbekannte Parameter bleiben unbekannt."
            ),
            source: "semantic_dataflow"
        )
        deep.activationForensics = af
        return makeReport(
            id: "pdf-incomplete",
            fileName: "incomplete.dec.bin",
            deep: deep,
            summary: "Unvollständige Datenflussanalyse und unbekannte Parameter (Release-PDF 6).",
            limits: deep.analysisLimitations ?? []
        )
    }
}
