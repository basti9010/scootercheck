# Cycle 9 — Agent C iOS Integration Report

Stand: 2026-11-23  
Branch: `cursor/ios-integration-cycle9-b100`  
Base: `cursor/prod-pipeline-forensic-c9-b100`

## Goal

Validate the Cycle-8 firmware forensics user flow on this lineage, strengthen offline XCTest coverage (status mapping, attach wiring, digests, encrypted→INCOMPLETE), and record iOS↔service E2E claim level without inventing secrets.

## Flow validation (code review)

| Step | Component | Status |
|------|-----------|--------|
| 1. Pick file | `FirmwareDocumentPicker` → `FirmwareForensicsAnalysisView.ingest` | Wired |
| 2. Local integrity | `FirmwareLocalAnalysisPipeline` (SHA-256/MD5 via `FirmwareDigest`) | Wired |
| 3. Authenticated job | `FirmwareServerAnalysisClient` (Settings API token + Client-Id; JWT absent on lineage) | Wired |
| 4. Status UI | `FirmwareAnalysisJobUIStatus` / mapper + badge in AnalysisView | Wired |
| 5. Result | Findings + server merge via `mergingServerResult` | Wired |
| 6. Save | Hub `onReportProduced` → `FirmwareInvestigationAttach` → `InvestigationStore.attachFirmwareReport` | Wired (helper extracted C9) |

Entry: `ContentView` sheet → `FirmwareForensicsHubView` → `FirmwareForensicsAnalysisView`.

**CrossSourceCorrelator:** not modified (no regression). Existing `CrossSourceCorrelatorTests` retained; smoke assertion added in new integration suite.

**Crypto gate:** encrypted / high-entropy without plaintext → `INCOMPLETE`; never `allowsSuccessfulDecompileClaim`. Confirmed in mapper + local pipeline + resolve(job:) paths.

## Files added / modified

| File | Role |
|------|------|
| `FirmwareForensics/FirmwareInvestigationAttach.swift` | Testable Hub→Store attach helper (resolve target + attach + soft error note) |
| `ScooterCheckTests/FirmwareForensicsFlowIntegrationTests.swift` | Offline integration tests (status resolve, digests, crypto gate, attach wiring, round-trip) |
| `ContentView.swift` | Uses `FirmwareInvestigationAttach.attach` instead of inline attach logic |
| `ScooterCheck.xcodeproj/project.pbxproj` | FE7 app source + FE8 test target wiring |
| `research/cycle9/agent_c/REPORT_IOS_INTEGRATION.md` | This report |

## New tests (`FirmwareForensicsFlowIntegrationTests`)

| Test | Covers |
|------|--------|
| `testResolveQueuedJobMapsToQueuedToken` | Status mapping via `resolve(job:)` |
| `testResolveProcessingStatesMapToProcessing` | decrypting/decompiling/extracting/llmEnrichment → PROCESSING |
| `testResolveFailedJobMapsToFailed` | FAILED wire state |
| `testResolveCompletedEncryptedWithoutPlaintextIsIncomplete` | encrypted → INCOMPLETE |
| `testResolveCompletedEncryptedWithPlaintextNoDecompileIsIncomplete` | plaintext without decompile → INCOMPLETE |
| `testResolveCompletedEncryptedWithPlaintextAndDecompileIsCompleted` | full artifacts → COMPLETED |
| `testResolveCompletenessHintEncryptedOverridesCompleted` | completeness hint gate |
| `testLocalPipelineDigestsMatchFirmwareDigestHelper` | SHA-256/MD5 integrity digests |
| `testLocalPipelineEncryptedFilenameProducesIncompleteNotCompleted` | encrypted → INCOMPLETE + completeness string |
| `testLocalPipelinePlaintextAllowsCompletedClaim` | plaintext / unknownFormat gate branches |
| `testAttachHelperCreatesInvestigationWhenActiveMissing` | attachFirmwareReport wiring helper |
| `testAttachHelperReusesActiveInvestigation` | reuse active investigation id |
| `testAttachHelperStaleActiveIdCreatesNew` | stale id → create |
| `testOfflineFlowPickAnalyzeGateAttachRoundTrip` | analyze → gate → attach → flush → reload |
| `testMergingServerCompletedWithoutPlaintextKeepsHonestLimits` | server merge honesty + INCOMPLETE |
| `testCrossSourceCorrelatorStillConfirmsMatchingFirmware` | correlator no-regression smoke |

Cycle-8 unit suite (`FirmwareAnalysisJobUIStatusTests`) remains; not duplicated wholesale.

## iOS ↔ service E2E

| Check | Result |
|-------|--------|
| `GET …/scootercheck-fw/health` (no auth) | HTTP 200, service up (`decryptConfigured`/`ghidraConfigured` true) |
| `POST …/v1/firmware/jobs` without credentials | HTTP 401 `missing or invalid credentials` |
| Authenticated submit + poll + UI | **NOT RUN** — no API token / JWT in this Cloud Agent environment (kickoff: no secret invention) |

**E2E claim level: NOT RUN** (live health reachable; authenticated job path not exercised). Offline integration path: **IMPLEMENTED** (tests authored; XCTest execution deferred to Codemagic — no Xcode on Linux agent image).

## Residual gaps

1. Live authenticated job E2E still pending secrets / device CI with Settings token or AuthSession JWT.
2. AuthSession JWT still unsupported on this lineage (API token + Client-Id path only).
3. Full ZipInspector / Orchestrator / ReferenceStore / KnownCFWCatalog not on tip (Cycle-8 residual).
4. Combined Hub path (`withReadout` + live Auslese reuse) still opens Auslesen rather than full attach reuse.
5. XCTest not executed on this agent image — CI expected.

## Epistemic grades

| Item | Grade |
|------|-------|
| Hub → Analysis → Store flow code | IMPLEMENTED |
| Crypto gate (encrypted → INCOMPLETE) | IMPLEMENTED (+ offline tests authored) |
| attachFirmwareReport wiring helper | IMPLEMENTED / TESTED (authored) |
| CrossSourceCorrelator unchanged | IMPLEMENTED (no edit) |
| Offline integration XCTest suite | IMPLEMENTED (CI execution pending) |
| Live iOS↔service job E2E | NOT RUN |
