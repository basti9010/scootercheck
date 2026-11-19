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
        // Yellow headline is Ampel-neutral; library/reference wording lives in bullets/rationale.
        XCTAssertTrue(
            brief.bullets.contains {
                $0.localizedCaseInsensitiveContains("Bibliothek") || $0.localizedCaseInsensitiveContains("Referenz")
            },
            "expected library/reference bullet, got: \(brief.bullets)"
        )
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

    func testPhase2FunctionDiffDecodesWithoutClaimingManipulation() throws {
        let json = """
        {
          "schemaVersion": 1,
          "producedAt": "2026-11-18T21:00:00Z",
          "sources": ["serverDecompile"],
          "subjectSHA256": "abc",
          "models": ["g3"],
          "speedLimits": [],
          "modeTransitions": [],
          "inputHints": [],
          "comboSummaries": [],
          "notes": [],
          "caveats": [],
          "quality": {"hasDeterministicBasis": true, "llmSchemaValidated": false, "summary": "ok"},
          "functionAnalysis": {"ok": true, "functionCount": 12, "processor": "ARM:LE:32:Cortex"},
          "functionDiff": {
            "ok": true,
            "summary": {
              "identical": 8,
              "structurallyChanged": 2,
              "added": 1,
              "removed": 1,
              "uncomparable": 0,
              "subjectFunctionCount": 12
            },
            "samplePairs": [
              {
                "status": "STRUKTURELL_VERAENDERT",
                "subject": {"address": "0x08001000", "name": "FUN_08001000", "size": 96},
                "evidenceTier": "statisch",
                "notes": "Struktureller Vergleich — keine Tuning-Aussage."
              }
            ],
            "analysisLimitations": ["Funktionsdiff ist kein Manipulationsnachweis."]
          },
          "referenceMetadata": {
            "referenceLabel": "G3 VCU community",
            "verificationStatus": "community",
            "referenceTrust": "communityLibrary"
          },
          "analysisLimitations": ["Kein Diaphora/BinDiff."]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let deep = try decoder.decode(FirmwareDeepAnalysisResult.self, from: json)
        XCTAssertEqual(deep.functionAnalysis?.functionCount, 12)
        XCTAssertEqual(deep.functionDiff?.summary?.structurallyChanged, 2)
        XCTAssertEqual(deep.functionDiff?.samplePairs?.first?.status, .structurallyChanged)
        XCTAssertEqual(deep.referenceMetadata?.verificationStatus, "community")
        XCTAssertTrue((deep.functionDiff?.analysisLimitations ?? []).contains {
            $0.contains("kein Manipulationsnachweis")
        })
        // Legacy clients ignore unknown keys — encoding round-trip keeps phase-1 fields.
        XCTAssertEqual(deep.schemaVersion, 1)
    }

    func testPhase22FCallgraphContainerRuntimeDecode() throws {
        let json = """
        {
          "schemaVersion": 1,
          "producedAt": "2026-11-19T10:00:00Z",
          "sources": ["serverDecompile", "serverEmulation"],
          "subjectSHA256": "def",
          "models": ["f3"],
          "speedLimits": [],
          "modeTransitions": [],
          "inputHints": [],
          "comboSummaries": [],
          "notes": [],
          "caveats": [],
          "quality": {"hasDeterministicBasis": true, "llmSchemaValidated": false, "summary": "ok"},
          "callGraph": {
            "ok": true,
            "edgeCount": 100,
            "unresolvedCount": 5,
            "callGraphQuality": {
              "directCalls": 40,
              "indirectCalls": 5,
              "internalBranches": 40,
              "tailCalls": 5,
              "unresolvedCalls": 5,
              "unknownControlFlow": 5
            }
          },
          "callGraphQuality": {
            "directCalls": 40,
            "indirectCalls": 5,
            "internalBranches": 40,
            "tailCalls": 5,
            "unresolvedCalls": 5,
            "unknownControlFlow": 5
          },
          "firmwareContainerAnalysis": {
            "ok": true,
            "status": "CONTAINER_RECOGNIZED",
            "format": "RAW4TFT",
            "containerRecognized": true,
            "architecture": null,
            "imageExtractable": true,
            "components": [
              {"origin": "RAW4TFT.payload", "offset": 1024, "size": 4096, "sha256": "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"}
            ],
            "analysisLimitations": ["Keine Architektur allein aus dem Dateinamen."]
          },
          "runtimeStateMachineValidation": {
            "ok": true,
            "dynamicRuntimeVerified": true,
            "runtimeTransitionsObserved": 2,
            "programCount": 6,
            "evidenceTier": "RUNTIME_TRANSITION_OBSERVED",
            "analysisLimitations": ["Unicorn-Test ist kein Nachweis realen Fahrzeugverhaltens."]
          },
          "analysisLimitations": ["Phase 2.2F"]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let deep = try decoder.decode(FirmwareDeepAnalysisResult.self, from: json)
        XCTAssertEqual(deep.callGraphQuality?.directCalls, 40)
        XCTAssertEqual(deep.callGraphQuality?.internalBranches, 40)
        XCTAssertEqual(deep.callGraph?.callGraphQuality?.unresolvedCalls, 5)
        XCTAssertEqual(deep.firmwareContainerAnalysis?.format, "RAW4TFT")
        XCTAssertEqual(deep.firmwareContainerAnalysis?.components?.first?.offset, 1024)
        XCTAssertEqual(deep.runtimeStateMachineValidation?.evidenceTier, "RUNTIME_TRANSITION_OBSERVED")
        XCTAssertTrue(deep.runtimeStateMachineValidation?.dynamicRuntimeVerified == true)
        XCTAssertTrue((deep.runtimeStateMachineValidation?.analysisLimitations ?? []).contains {
            $0.localizedCaseInsensitiveContains("Fahrzeug")
        })
        XCTAssertTrue(deep.speedLimits.isEmpty)
    }

    func testPhase22GAnalysisProfileDecode() throws {
        let json = """
        {
          "schemaVersion": 1,
          "producedAt": "2026-11-19T11:00:00Z",
          "sources": ["serverDecompile"],
          "subjectSHA256": "g22",
          "models": ["f3"],
          "speedLimits": [],
          "modeTransitions": [],
          "inputHints": [],
          "comboSummaries": [],
          "notes": [],
          "caveats": [],
          "quality": {"hasDeterministicBasis": true, "llmSchemaValidated": false, "summary": "ok"},
          "analysisProfile": {
            "analysisProfileVersion": "2.2G.1",
            "analysisProfileHash": "abcd1234ffff",
            "analyzerCompat": "2",
            "ghidraVersion": "12.2_PUBLIC",
            "processorArchitecture": "ARM:LE:32:Cortex",
            "requestedLoaderBase": "0x08000000",
            "seedCortexMEntryPoints": true
          },
          "analysisProfileHash": "abcd1234ffff",
          "ghidraAddressLayout": {
            "requestedLoaderBase": "0x08000000",
            "actualImageBase": "00000000",
            "memoryBlockStart": "08000000",
            "resetHandlerAddress": "0x08000101"
          },
          "firmwareArchitectureConfidence": "ARCHITECTURE_UNKNOWN",
          "runtimeValidationDetails": {
            "tool": "unicorn-fsm-runtime",
            "threeStateReproducible": true,
            "vehicleTest": false,
            "evidenceTier": "RUNTIME_TRANSITION_OBSERVED"
          }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let deep = try decoder.decode(FirmwareDeepAnalysisResult.self, from: json)
        XCTAssertEqual(deep.analysisProfile?.analysisProfileVersion, "2.2G.1")
        XCTAssertEqual(deep.analysisProfileHash, "abcd1234ffff")
        XCTAssertEqual(deep.ghidraAddressLayout?.requestedLoaderBase, "0x08000000")
        XCTAssertEqual(deep.firmwareArchitectureConfidence, "ARCHITECTURE_UNKNOWN")
        XCTAssertEqual(deep.runtimeValidationDetails?.vehicleTest, false)
        XCTAssertEqual(deep.runtimeValidationDetails?.threeStateReproducible, true)
    }
}
