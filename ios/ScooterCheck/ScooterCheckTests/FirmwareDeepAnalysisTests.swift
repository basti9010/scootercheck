import XCTest
@testable import ScooterCheck

final class FirmwareDeepAnalysisTests: XCTestCase {

    func testKnownCatalogMatchesG3PanicbuttonHash() throws {
        let entry = FirmwareKnownCFWCatalog.match(
            md5: "0a567b134861a5f9f7e4683e63d8f4a8",
            sha256: "929a01874b64c1e7dd075648d45d0c12305bff9bb3cc236d58a3fb6e1dba2180"
        )
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.displayName, "Panicbutton (Starke-Tech.de)")

        let deep = FirmwareKnownCFWCatalog.deepAnalysis(
            for: try XCTUnwrap(entry),
            subjectSHA256: "929a01874b64c1e7dd075648d45d0c12305bff9bb3cc236d58a3fb6e1dba2180"
        )
        XCTAssertTrue(deep.quality.hasDeterministicBasis)
        XCTAssertEqual(deep.maxSpeedKmhInCode, 99)
        XCTAssertEqual(deep.legalCapKmhInCode, 20)
        XCTAssertTrue(deep.comboSummaries.isEmpty, "catalog must not invent unlock button recipes")
        XCTAssertTrue(deep.inputHints.contains { $0.kind == .customButton || $0.kind == .dualAnalog })
    }

    func testDecompileScanFindsPackedSpeeds() {
        let snippet = """
        void FUN_test(void) {
          *(undefined2 *)(iVar6 + 0x8c) = 0x1400;
          uVar5 = 0x1600;
          uVar5 = 0x1900;
          uVar5 = 0x6300;
          *(undefined2 *)(iVar6 + 0x8c) = 0x2000;
        }
        """
        let meta = FirmwarePackageMeta(
            schemaVersion: 1,
            displayName: "test",
            models: ["g3"],
            type: "VCU",
            compatible: [],
            declaredMd5: nil,
            declaredEncrypted: false,
            rawInfoJSON: nil
        )
        let deep = FirmwareSpeedSignatureExtractor.extract(
            fromBinary: nil,
            decompiledText: snippet,
            subjectSHA256: "abc",
            meta: meta
        )
        XCTAssertTrue(deep.quality.hasDeterministicBasis)
        XCTAssertEqual(deep.maxSpeedKmhInCode, 99)
        XCTAssertEqual(deep.legalCapKmhInCode, 20)
        let kmhs = Set(deep.speedLimits.map(\.kmh))
        XCTAssertTrue(kmhs.contains(22))
        XCTAssertTrue(kmhs.contains(32))
        XCTAssertTrue(deep.comboSummaries.isEmpty, "speed pairs must not invent button combos")
        XCTAssertFalse(deep.modeTransitions.isEmpty)
        XCTAssertEqual(deep.modeTransitions.first?.trigger, FirmwareComboPolicy.unbelegtTrigger)
    }

    func testDecompileInputTokensWithoutInventedCombo() {
        let snippet = """
        // throttle adc > 400 and brake lever, mask & 3 both channels, power boot
        if ((mask & 3) == 3 && throttle > 400 && brake > 400) {
          speed = 0x6300;
        } else {
          speed = 0x1600;
        }
        """
        let meta = FirmwarePackageMeta(
            schemaVersion: 1,
            displayName: "combo",
            models: ["g3"],
            type: "VCU",
            compatible: [],
            declaredMd5: nil,
            declaredEncrypted: false,
            rawInfoJSON: nil
        )
        let deep = FirmwareSpeedSignatureExtractor.extract(
            fromBinary: nil,
            decompiledText: snippet,
            subjectSHA256: "combo",
            meta: meta
        )
        XCTAssertTrue(deep.comboSummaries.isEmpty)
        XCTAssertTrue(deep.inputHints.contains { $0.kind == .dualAnalog || $0.kind == .throttle })
        XCTAssertTrue(deep.modeTransitions.contains { $0.title.localizedCaseInsensitiveContains("Limit") })
        XCTAssertFalse(deep.modeTransitions.contains { $0.trigger.localizedCaseInsensitiveContains("Gas") })
    }

    func testBinaryScanFindsLEPackedU16() {
        // little-endian 0x1600 → bytes 00 16; 0x6300 → 00 63
        let data = Data([0x00, 0x16, 0xFF, 0x00, 0x63])
        let meta = FirmwarePackageMeta(
            schemaVersion: 1,
            displayName: nil,
            models: [],
            type: nil,
            compatible: [],
            declaredMd5: nil,
            declaredEncrypted: nil,
            rawInfoJSON: nil
        )
        let deep = FirmwareSpeedSignatureExtractor.extract(
            fromBinary: data,
            decompiledText: nil,
            subjectSHA256: "bin",
            meta: meta
        )
        XCTAssertEqual(deep.maxSpeedKmhInCode, 99)
        XCTAssertTrue(deep.speedLimits.contains { $0.kmh == 22 })
    }

    func testMergerPrefersCatalogAndValidateRejectsEmptyLLM() {
        let entry = FirmwareKnownCFWCatalog.g3PanicbuttonStarkeTech
        let cat = FirmwareKnownCFWCatalog.deepAnalysis(for: entry, subjectSHA256: "x")
        let emptyLLM = FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(),
            sources: [.serverLLM],
            subjectSHA256: "x",
            packageDisplayName: nil,
            models: [],
            controllerType: nil,
            speedLimits: [],
            maxSpeedKmhInCode: nil,
            legalCapKmhInCode: nil,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: [],
            caveats: [],
            quality: .init(hasDeterministicBasis: false, llmSchemaValidated: false, summary: "")
        )
        XCTAssertNil(FirmwareDeepAnalysisMerger.validateServerResult(emptyLLM))

        let merged = FirmwareDeepAnalysisMerger.merge([cat])
        XCTAssertEqual(merged?.maxSpeedKmhInCode, 99)
    }

    func testBriefingPrefersHumanCombosAndRefreshesGrayVerdict() {
        let deep = FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(),
            sources: [.serverDecompile, .serverLLM],
            subjectSHA256: "abc",
            packageDisplayName: "ZT3",
            models: ["zt3"],
            controllerType: "VCU",
            speedLimits: [
                FirmwareSpeedLimitFinding(
                    id: "a", kmh: 20, packedU16: 0x1400, role: .legalCap,
                    evidence: "x", source: .serverDecompile, confidence: .high
                ),
                FirmwareSpeedLimitFinding(
                    id: "b", kmh: 99, packedU16: 0x6300, role: .openCap,
                    evidence: "y", source: .serverDecompile, confidence: .high
                )
            ],
            maxSpeedKmhInCode: 99,
            legalCapKmhInCode: 20,
            modeTransitions: [
                FirmwareModeTransitionFinding(
                    id: "t1", title: "Zwei Limit-Welten im Code", trigger: "Tastenkombi",
                    effect: "20↔99", evidence: "e", source: .serverDecompile, confidence: .medium
                ),
                FirmwareModeTransitionFinding(
                    id: "t2", title: "Pfad zu 35 km/h (0x2300)", trigger: "Capstone-Rückwärts",
                    effect: "Immediate", evidence: "e", source: .serverCapstone, confidence: .low
                )
            ],
            inputHints: [
                FirmwareInputHintFinding(
                    id: "i1", kind: .throttle, detail: "Gas-Kanal",
                    evidence: "e", source: .serverDecompile, confidence: .medium
                ),
                FirmwareInputHintFinding(
                    id: "i2", kind: .customButton, detail: "puVar5[3]==0x02",
                    evidence: "e", source: .serverLLM, confidence: .low
                )
            ],
            comboSummaries: [
                "Vermutete Soft-/Power-Kombi: Gas + Bremse + Power — Live-Test nötig",
                "Live-Kombination (SN): Gas+Bremse+Power",
                "Bitfeld-Manipulation: puVar1[0] mit 0x2000"
            ],
            notes: ["llm=schema-enriched"],
            caveats: [],
            quality: .init(hasDeterministicBasis: true, llmSchemaValidated: true, summary: "ok"),
            stockDiff: FirmwareStockDiffResult(
                outcome: .identical,
                referenceId: "r1",
                referenceLabel: "ZT3 VCU 48KMH sim",
                referenceSHA256: "x",
                differingBytes: nil,
                firstDiffOffset: nil,
                subjectBytes: nil,
                referenceBytes: nil,
                percentDifferent: nil,
                segments: [],
                note: "SHA-256 identisch"
            )
        )
        let brief = FirmwareDeepAnalysisBriefing.build(from: deep)
        XCTAssertTrue(brief.headline.localizedCaseInsensitiveContains("Referenz") || brief.headline.localizedCaseInsensitiveContains("Bibliothek"))
        XCTAssertEqual(brief.actionableCombos, ["Live-Kombination (SN): Gas+Bremse+Power"])
        XCTAssertTrue(brief.technicalCombos.contains { $0.localizedCaseInsensitiveContains("Bitfeld") })
        XCTAssertFalse(brief.actionableCombos.contains { $0.localizedCaseInsensitiveContains("Vermutete") })
        XCTAssertEqual(brief.humanModeTransitions.count, 1)
        XCTAssertEqual(brief.humanModeTransitions.first?.trigger, FirmwareComboPolicy.unbelegtTrigger)
        XCTAssertEqual(brief.technicalModeTransitions.count, 1)
        let refreshed = FirmwareDeepAnalysisBriefing.refreshedVerdict(
            current: .gray,
            rationale: "encrypted",
            deep: deep
        )
        // Community/OEM without provenanceVerified → YELLOW, not automatic GREEN.
        XCTAssertEqual(refreshed.0, .yellow)
        XCTAssertTrue(
            refreshed.1.localizedCaseInsensitiveContains("Bibliothek")
                || refreshed.1.localizedCaseInsensitiveContains("nicht bestätigt")
                || refreshed.1.localizedCaseInsensitiveContains("Referenz")
        )
    }

    func testAmpelGreenOnlyWithVerifiedReference() {
        var stock = FirmwareStockDiffResult(
            outcome: .identical,
            referenceId: "v1",
            referenceLabel: "OEM verified",
            referenceSHA256: "aaa",
            differingBytes: 0,
            firstDiffOffset: nil,
            subjectBytes: 100,
            referenceBytes: 100,
            percentDifferent: 0,
            segments: [],
            note: "SHA identical",
            referenceTrust: FirmwareReferenceTrust.manufacturerVerified.rawValue,
            referenceProvenanceVerified: true
        )
        let deepGreen = makeDeep(stock: stock, sources: [.serverDecompile])
        let green = FirmwareDeepAnalysisBriefing.refreshedVerdict(current: .gray, rationale: "", deep: deepGreen)
        XCTAssertEqual(green.0, .green)

        stock.referenceTrust = FirmwareReferenceTrust.communityLibrary.rawValue
        stock.referenceProvenanceVerified = false
        stock.referenceSource = "oem"
        let deepYellow = makeDeep(stock: stock, sources: [.serverDecompile])
        let yellow = FirmwareDeepAnalysisBriefing.refreshedVerdict(current: .gray, rationale: "", deep: deepYellow)
        XCTAssertEqual(yellow.0, .yellow)
    }

    func testAmpelByteDiffAloneIsYellowNotRed() {
        let stock = FirmwareStockDiffResult(
            outcome: .different,
            referenceId: "r",
            referenceLabel: "stock",
            referenceSHA256: "b",
            referenceSource: "oem",
            differingBytes: 12,
            firstDiffOffset: 0x100,
            subjectBytes: 1000,
            referenceBytes: 1000,
            percentDifferent: 1.2,
            segments: [],
            note: "12 bytes differ",
            limitRegionAffected: false,
            panicRegionAffected: false,
            referenceTrust: FirmwareReferenceTrust.communityLibrary.rawValue,
            referenceProvenanceVerified: false
        )
        let deep = makeDeep(stock: stock, sources: [.serverDecompile], yara: [])
        let v = FirmwareDeepAnalysisBriefing.refreshedVerdict(current: .gray, rationale: "", deep: deep)
        XCTAssertEqual(v.0, .yellow)
        XCTAssertFalse(v.1.localizedCaseInsensitiveContains("ROT"))
    }

    func testAmpelMissingReferenceIsGrayOrYellow() {
        let stock = FirmwareStockDiffResult(
            outcome: .noReference,
            referenceId: nil,
            referenceLabel: nil,
            referenceSHA256: nil,
            differingBytes: nil,
            firstDiffOffset: nil,
            subjectBytes: 10,
            referenceBytes: nil,
            percentDifferent: nil,
            segments: [],
            note: "no ref"
        )
        let deep = makeDeep(stock: stock, sources: [])
        let v = FirmwareDeepAnalysisBriefing.refreshedVerdict(current: .gray, rationale: "encrypted", deep: deep)
        XCTAssertEqual(v.0, .gray)
    }

    func testAmpelYaraAloneNotRed() {
        let yara = [
            FirmwareYaraMatch(
                rule: "soft_unlock_hint",
                description: "pattern",
                confidence: "medium",
                family: "soft-unlock",
                tags: [],
                strings: []
            )
        ]
        let deep = makeDeep(stock: nil, sources: [.serverYara], yara: yara)
        let v = FirmwareDeepAnalysisBriefing.refreshedVerdict(current: .yellow, rationale: "x", deep: deep)
        XCTAssertNotEqual(v.0, .red)
    }

    func testMergerKeepsIvtAndPinoutAndDoesNotOverwriteWithNil() {
        let withIvt = FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(),
            sources: [.serverIvt],
            subjectSHA256: "s",
            packageDisplayName: nil,
            models: ["g3"],
            controllerType: "VCU",
            speedLimits: [
                FirmwareSpeedLimitFinding(
                    id: "s1", kmh: 20, packedU16: 0x1400, role: .legalCap,
                    evidence: "e", source: .serverIvt, confidence: .medium
                )
            ],
            maxSpeedKmhInCode: 20,
            legalCapKmhInCode: 20,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: [],
            caveats: [],
            quality: .init(hasDeterministicBasis: true, llmSchemaValidated: false, summary: "ivt"),
            cortexMIvt: FirmwareCortexMIvt(
                likely: true, flashBase: "0x08000000", initialSP: "0x20020000",
                resetHandler: "0x08001234", resetFileOffset: 0x1234, resetThumb: true
            ),
            boardPinout: FirmwareBoardPinoutHint(id: "g3-vcu", notes: "AT32 hint")
        )
        let withoutOptional = FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(),
            sources: [.serverDecompile],
            subjectSHA256: "s",
            packageDisplayName: nil,
            models: ["g3"],
            controllerType: "VCU",
            speedLimits: [
                FirmwareSpeedLimitFinding(
                    id: "s2", kmh: 99, packedU16: 0x6300, role: .openCap,
                    evidence: "e", source: .serverDecompile, confidence: .high
                )
            ],
            maxSpeedKmhInCode: 99,
            legalCapKmhInCode: 20,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: ["decompile"],
            caveats: [],
            quality: .init(hasDeterministicBasis: true, llmSchemaValidated: false, summary: "dec")
        )
        let merged = FirmwareDeepAnalysisMerger.merge([withIvt, withoutOptional])
        XCTAssertNotNil(merged?.cortexMIvt)
        XCTAssertEqual(merged?.cortexMIvt?.resetHandler, "0x08001234")
        XCTAssertEqual(merged?.boardPinout?.id, "g3-vcu")
        XCTAssertEqual(merged?.maxSpeedKmhInCode, 99)

        let coalesced = FirmwareDeepAnalysisMerger.coalesceOptionals(base: withIvt, incoming: withoutOptional)
        XCTAssertNotNil(coalesced.cortexMIvt)
        XCTAssertNotNil(coalesced.boardPinout)
    }

    func testEvidenceClassifierDoesNotUpgradeYaraToLive() {
        let deep = makeDeep(
            stock: nil,
            sources: [.serverYara, .serverEmulation],
            yara: [
                FirmwareYaraMatch(
                    rule: "cfw", description: "x", confidence: "high",
                    family: "cfw", tags: [], strings: []
                )
            ]
        )
        let findings = FirmwareEvidenceClassifier.classify(from: deep)
        XCTAssertTrue(findings.contains { $0.category == "yara" && $0.tier == .muster })
        XCTAssertTrue(findings.contains { $0.category == "emulation" && $0.tier == .emuliert })
        XCTAssertFalse(findings.contains { $0.category == "yara" && $0.tier == .live })
    }

    func testScorerByteDiffIsYellowNotRed() {
        let crypto = plaintextCrypto()
        let cmp = FirmwareComparisonResult(
            outcome: .different,
            referenceId: "r",
            referenceLabel: "ref",
            differingBytes: 4,
            firstDiffOffset: 0,
            segments: [],
            note: "diff — hersteller-/intern verifiziert oem-confirmed", // text must be ignored
            referenceTrust: FirmwareReferenceTrust.communityLibrary.rawValue,
            referenceProvenanceVerified: false,
            functionalChangeVerified: false
        )
        let (v, _) = FirmwareForensicScorer.score(
            crypto: crypto, comparison: cmp, evidence: [], hasPrimaryPayload: true
        )
        XCTAssertEqual(v, .yellow)
    }

    func testScorerIgnoresNoteTextForGreen() {
        let crypto = plaintextCrypto()
        // Misleading note claiming verified — structured fields say community.
        let cmp = FirmwareComparisonResult(
            outcome: .identical,
            referenceId: "r",
            referenceLabel: "community",
            differingBytes: 0,
            firstDiffOffset: nil,
            segments: [],
            note: "SHA identical. Referenzvertrauen: hersteller-/intern verifiziert.",
            referenceTrust: FirmwareReferenceTrust.communityLibrary.rawValue,
            referenceProvenanceVerified: false,
            functionalChangeVerified: false
        )
        let (v, _) = FirmwareForensicScorer.score(
            crypto: crypto, comparison: cmp, evidence: [], hasPrimaryPayload: true
        )
        XCTAssertEqual(v, .yellow)
        XCTAssertTrue(cmp.comparisonStatus == .identical)
        XCTAssertFalse(cmp.allowsGreenIdentity)
    }

    func testScorerGreenRequiresStructuredProvenance() {
        let crypto = plaintextCrypto()
        let cmp = FirmwareComparisonResult(
            outcome: .identical,
            referenceId: "r",
            referenceLabel: "OEM",
            differingBytes: 0,
            firstDiffOffset: nil,
            segments: [],
            note: "identical",
            referenceTrust: FirmwareReferenceTrust.manufacturerVerified.rawValue,
            referenceProvenanceVerified: true,
            functionalChangeVerified: false
        )
        let (v, _) = FirmwareForensicScorer.score(
            crypto: crypto, comparison: cmp, evidence: [], hasPrimaryPayload: true
        )
        XCTAssertEqual(v, .green)
    }

    func testScorerRedOnlyWhenFunctionalChangeVerified() {
        let crypto = plaintextCrypto()
        var cmp = FirmwareComparisonResult(
            outcome: .different,
            referenceId: "r",
            referenceLabel: "OEM",
            differingBytes: 40,
            firstDiffOffset: 0,
            segments: [],
            note: "diff",
            referenceTrust: FirmwareReferenceTrust.manufacturerVerified.rawValue,
            referenceProvenanceVerified: true,
            functionalChangeVerified: false
        )
        XCTAssertEqual(
            FirmwareForensicScorer.score(crypto: crypto, comparison: cmp, evidence: [], hasPrimaryPayload: true).0,
            .yellow
        )
        cmp.functionalChangeVerified = true
        XCTAssertEqual(
            FirmwareForensicScorer.score(crypto: crypto, comparison: cmp, evidence: [], hasPrimaryPayload: true).0,
            .red
        )
    }

    func testScorerNoPayloadIsGrayNotGreen() {
        let (v, _) = FirmwareForensicScorer.score(
            crypto: plaintextCrypto(),
            comparison: nil,
            evidence: [],
            hasPrimaryPayload: false
        )
        XCTAssertEqual(v, .gray)
    }

    func testComparerSetsStructuredTrustFields() {
        let firm = Data("REF_BYTES_STRUCTURED_TRUST_01".utf8)
        let verified = FirmwareReferenceRecord(
            id: "v",
            manufacturer: "Ninebot",
            model: "g3",
            controllerType: "VCU",
            hardwareVersion: "AT32",
            firmwareVersion: "1.0",
            sha256: FirmwareDigest.sha256Hex(firm),
            md5: FirmwareDigest.md5Hex(firm),
            byteCount: firm.count,
            origin: "lab",
            verificationStatus: .verified,
            createdAt: Date(),
            plaintextBytes: firm
        )
        let identical = FirmwareComparer.compare(
            subjectSHA256: verified.sha256,
            subjectData: firm,
            encrypted: false,
            references: [verified],
            preferredId: nil
        )
        XCTAssertEqual(identical.outcome, .identical)
        XCTAssertEqual(identical.referenceTrust, FirmwareReferenceTrust.manufacturerVerified.rawValue)
        XCTAssertEqual(identical.referenceProvenanceVerified, true)
        XCTAssertEqual(identical.functionalChangeVerified, false)
        XCTAssertTrue(identical.allowsGreenIdentity)

        let community = FirmwareReferenceRecord(
            id: "c",
            manufacturer: "Ninebot",
            model: "g3",
            controllerType: "VCU",
            hardwareVersion: "AT32",
            firmwareVersion: "1.0",
            sha256: FirmwareDigest.sha256Hex(firm),
            md5: FirmwareDigest.md5Hex(firm),
            byteCount: firm.count,
            origin: "community",
            verificationStatus: .userImported,
            createdAt: Date(),
            plaintextBytes: firm
        )
        let sameHash = FirmwareComparer.compare(
            subjectSHA256: community.sha256,
            subjectData: firm,
            encrypted: false,
            references: [community],
            preferredId: nil
        )
        XCTAssertEqual(sameHash.referenceTrust, FirmwareReferenceTrust.communityLibrary.rawValue)
        XCTAssertEqual(sameHash.referenceProvenanceVerified, false)
        XCTAssertFalse(sameHash.allowsGreenIdentity)

        var tweaked = firm
        tweaked[0] ^= 0xFF
        let diff = FirmwareComparer.compare(
            subjectSHA256: FirmwareDigest.sha256Hex(tweaked),
            subjectData: tweaked,
            encrypted: false,
            references: [verified],
            preferredId: verified.id
        )
        XCTAssertEqual(diff.outcome, .different)
        XCTAssertEqual(diff.functionalChangeVerified, false)
    }

    private func plaintextCrypto() -> FirmwareCryptoAssessment {
        FirmwareCryptoAssessment(
            status: .plaintext,
            detectedFormat: "bin",
            decryptionAvailable: false,
            decryptionNote: "",
            evidence: []
        )
    }

    private func makeDeep(
        stock: FirmwareStockDiffResult?,
        sources: [FirmwareDeepAnalysisSource],
        yara: [FirmwareYaraMatch] = []
    ) -> FirmwareDeepAnalysisResult {
        FirmwareDeepAnalysisResult(
            schemaVersion: 1,
            producedAt: Date(),
            sources: sources,
            subjectSHA256: "subj",
            packageDisplayName: nil,
            models: ["zt3"],
            controllerType: "VCU",
            speedLimits: [],
            maxSpeedKmhInCode: nil,
            legalCapKmhInCode: nil,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: [],
            caveats: [],
            quality: .init(hasDeterministicBasis: true, llmSchemaValidated: false, summary: "t"),
            stockDiff: stock,
            yaraMatches: yara
        )
    }

    func testOrchestratorAttachesCatalogDeepAnalysisForMatchingENC() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("G3_VCU_Panicbutton_2026.zip")
        let data = try Data(contentsOf: fixtures)
        let report = FirmwareForensicOrchestrator.analyze(
            fileName: "G3_VCU_Panicbutton_2026.zip",
            data: data
        )
        let deep = try XCTUnwrap(report.deepAnalysis)
        XCTAssertTrue(deep.quality.hasDeterministicBasis)
        XCTAssertEqual(deep.maxSpeedKmhInCode, 99)
        XCTAssertEqual(deep.legalCapKmhInCode, 20)
        XCTAssertTrue(deep.sources.contains(.knownCatalog))
        XCTAssertTrue(deep.comboSummaries.isEmpty, "hash catalog must not claim unverified unlock combos")
    }
}
