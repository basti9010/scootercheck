import XCTest
import PDFKit
@testable import ScooterCheck

/// Guards the firmware-forensics export write path used by "PDF exportieren".
final class FirmwareForensicPDFExportShareTests: XCTestCase {

    func testRenderedPDFCanBeWrittenAtomicallyForShareSheet() throws {
        var deep = FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sources: [.serverDecompile],
            subjectSHA256: String(repeating: "a", count: 64),
            packageDisplayName: "Export Share Fixture",
            models: ["test"],
            controllerType: "VCU",
            speedLimits: [],
            maxSpeedKmhInCode: nil,
            legalCapKmhInCode: nil,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: ["Export-Test"],
            caveats: ["Unit-Test"],
            quality: .init(hasDeterministicBasis: true, llmSchemaValidated: false, summary: "synthetic"),
            stockDiff: nil,
            yaraMatches: []
        )
        deep.analysisCompleteness = "PARTIAL"
        deep.referenceMetadata = FirmwareReferenceMetadata(
            referenceLabel: "community",
            referenceTrust: "communityLibrary",
            verificationStatus: "community"
        )

        let digest = FirmwareFileDigest(
            md5: "d41d8cd98f00b204e9800998ecf8427e",
            sha256: deep.subjectSHA256 ?? "x",
            byteCount: 128,
            shannonEntropy: 4.0
        )
        let report = FirmwareForensicReport(
            id: "export-share",
            analyzedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalFileName: "export.bin",
            containerKind: .bareBinary,
            archiveByteCount: 128,
            archiveDigest: digest,
            meta: FirmwarePackageMeta(
                schemaVersion: 1,
                displayName: "Export",
                models: ["test"],
                type: "VCU",
                compatible: [],
                declaredMd5: nil,
                declaredEncrypted: false,
                rawInfoJSON: nil
            ),
            entries: [],
            primaryFirmwarePath: "export.bin",
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
            verdictRationale: "Export-Test",
            limits: ["Unit-Test"],
            vehicleContext: nil,
            vehicleLinkNotes: [],
            summary: "PDF-Export Share Fixture",
            deepAnalysis: deep,
            serverArtifacts: FirmwareServerArtifacts(
                jobId: "job-export",
                plaintextSaved: true,
                plaintextSHA256: deep.subjectSHA256,
                plaintextByteCount: 128,
                decompileSaved: false,
                decompileExcerpt: nil
            )
        )

        let pdf = FirmwareForensicPDF.render(report)
        XCTAssertGreaterThan(pdf.count, 500)
        XCTAssertEqual(String(data: pdf.prefix(5), encoding: .ascii), "%PDF-")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScooterCheck-Firmware-Forensik-export-share-\(UUID().uuidString).pdf")
        try pdf.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan((attrs[.size] as? NSNumber)?.intValue ?? 0, 500)

        let named = NamedShareFile(url: url, title: "ScooterCheck Firmware-Forensik", utType: "com.adobe.pdf")
        XCTAssertEqual(named.url, url)
        XCTAssertTrue(named.title.contains("Forensik"))
        XCTAssertNotNil(PDFDocument(url: url))
    }
}
