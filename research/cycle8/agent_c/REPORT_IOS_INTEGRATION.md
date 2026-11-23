# Cycle 8 — Agent C iOS Integration Report

Stand: 2026-11-23  
Branch: `cursor/ios-firmware-forensics-hub-b100`  
Base: `cursor/server-deploy-ghidra-ios-c8-b100`

## Goal

Wire a complete firmware forensics user flow on this lineage using components already on tip, port the missing Hub, distinguish job statuses (including crypto gate), and attach results to `InvestigationStore`.

## Status enum mapping

| UI token | Source |
|----------|--------|
| `QUEUED` | `FirmwareAnalysisJobState.queued` |
| `PROCESSING` | `decrypting` / `decompiling` / `extracting` / `llmEnrichment` |
| `COMPLETED` | wire `completed` **and** crypto gate allows (plaintext or server plaintext+decompile) |
| `FAILED` | wire `failed` / `notConfigured` / client errors |
| `UNSUPPORTED` | unknown format without artifacts, or completeness hint `*UNSUPPORTED*` |
| `INCOMPLETE` | encrypted / high-entropy without plaintext (or plaintext without decompile); completeness `INCOMPLETE*` / `ENCRYPTED*` |

Mapper: `FirmwareAnalysisJobUIStatus` + `FirmwareAnalysisJobUIStatusMapper`  
Crypto gate rule: encrypted firmware is **never** shown as successfully decompiled (`allowsSuccessfulDecompileClaim == false` for INCOMPLETE/UNSUPPORTED).

## Files added

| File | Role |
|------|------|
| `FirmwareForensics/FirmwareForensicsHubView.swift` | Minimal Hub port (unified-investigation-flow) |
| `FirmwareForensics/FirmwareForensicsAnalysisView.swift` | Cycle-8 flow UI: pick → integrity → job → status → findings → save |
| `FirmwareForensics/FirmwareDocumentPicker.swift` | UIKit document picker (sheet-safe) |
| `FirmwareForensics/FirmwareLocalAnalysisPipeline.swift` | PackageLoader + CryptoAssessor + BinaryStaticAnalyzer + Scorer |
| `FirmwareForensics/FirmwareAnalysisJobUIStatus.swift` | Status enum + crypto gate mapper |
| `ScooterCheckTests/FirmwareAnalysisJobUIStatusTests.swift` | Status mapping / crypto gate / API-token auth tests |
| `research/cycle8/agent_c/REPORT_IOS_INTEGRATION.md` | This report |

## Files modified

| File | Change |
|------|--------|
| `FirmwareServerAnalysisClient.swift` | Settings API token (+ Client-Id) accepted when AuthSession JWT absent (`hasAuthCredential`) |
| `ContentView.swift` | Hub sheet + `onReportProduced` → `InvestigationStore.attachFirmwareReport`; menu/hub entry points |
| `ScooterCheck.xcodeproj/project.pbxproj` | Sources + Tests group / build phases for new files |

## Flow (wired)

1. Investigation Hub / menu / Auslesen → `FirmwareForensicsHubView`
2. Mode → `FirmwareForensicsAnalysisView`
3. Pick file (`FirmwareDocumentPicker`) → local pipeline (SHA-256/MD5 integrity + crypto + static)
4. Optional: create server job (`FirmwareServerAnalysisClient`) using Settings URL/token
5. Poll + show UI status badge (`QUEUED`…`INCOMPLETE`)
6. Display findings; **Save** → `onReportProduced` → `attachFirmwareReport`

`CrossSourceCorrelator` (MULTI / BLE–Enc2–WriteGate) was **not** changed.

## Test names

- `testQueuedMapsToQueued`
- `testProcessingStatesMapToProcessing`
- `testCompletedAndFailedWireMapping`
- `testEncryptedWithoutPlaintextIsIncompleteNotCompleted`
- `testLikelyEncryptedWithoutPlaintextIsIncomplete`
- `testUnknownFormatWithoutArtifactsIsUnsupported`
- `testPlaintextCompletedStaysCompleted`
- `testEncryptedWithPlaintextAndDecompileIsCompleted`
- `testEncryptedWithPlaintextButNoDecompileIsIncomplete`
- `testInFlightStatesIgnoreCryptoGate`
- `testCompletenessHintOverridesCompleted`
- `testLocalPipelineEncryptedProducesIncompleteUIStatus`
- `testLocalPipelineExposesIntegrityDigests`
- `testServerClientAcceptsAPITokenWithoutJWT`
- `testServerClientLoginRequiredWithoutAnyCredential`

## Residual gaps

1. **Full ZipInspector (unified ~2.2k LOC)** not ported — DualSource panic cards, PDF/JSON export session, reference import, decompile preview sheet remain on older branches.
2. **Orchestrator / ReferenceStore / KnownCFWCatalog / SpeedSignatureExtractor / DeepAnalysisMerger** still missing on this lineage; local pipeline is intentionally minimal.
3. **AuthSession JWT** not invented; Settings API token path only. Production with `TRUST_API_TOKEN_CLIENT_ID=0` may still reject Client-Id ownership — JWT login remains preferred when available.
4. **Combined flow** (`withReadout` + live vehicle context from current Auslese) not fully wired from Investigation Hub combined path (reuse prompt still opens Auslesen).
5. Legacy `FirmwareZipInspectorView` (ZIP-string analyzer) remains in the target but is no longer the primary entry.
6. **E2E against live api.tuningscanner.de** not verified from this Cloud Agent VM (host/secrets constraints per Cycle-8 kickoff).
7. XCTest not executed here (no Xcode on Linux agent image) — CI Codemagic expected.

## Epistemic

| Item | Grade |
|------|-------|
| Hub + analysis flow code present | IMPLEMENTED |
| Status / crypto-gate unit tests authored | IMPLEMENTED |
| attachFirmwareReport wiring | IMPLEMENTED |
| Live server job E2E | NOT_TESTED |
| AuthSession JWT | UNSUPPORTED on this lineage |
