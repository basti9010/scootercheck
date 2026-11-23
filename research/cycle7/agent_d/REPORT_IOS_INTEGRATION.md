# Cycle 7 AGENT D – iOS Integration Gaps

**Stand:** 2026-11-23  
**Compare:** multi-agent tip vs unified investigation flow  
**MULTI:** `origin/cursor/multi-agent-system-b100` @ `f2db879`  
**UNIFIED:** `origin/cursor/unified-investigation-flow-b100` @ `f306bf3`  
**merge-base:** `bd5a740`

**Verdict:** Investigation Store/Hub + DeepAnalysis **Codable** foundation are already on MULTI and **byte-identical** to UNIFIED. The gap is the **runtime analysis pipeline** (loader → orchestrator → server client → modern inspector/hub) and the **ContentView wire** that never calls `attachFirmwareReport`. Do **not** wholesale-merge UNIFIED (auth/Ghidra lineage + ContentView noise). Keep MULTI P0 BLE / Enc2 / WriteGate and MULTI-only `CrossSourceCorrelator`.

---

## 1. Present / missing matrix

| Surface | MULTI tip | UNIFIED tip | Notes |
|---------|-----------|-------------|-------|
| `FirmwareServerAnalysisClient` | **MISSING** | PRESENT | submit/poll + admin APIs; needs JWT |
| `FirmwarePackageLoader` | **MISSING** | PRESENT | ZIP/ENC/BIN inventory + `info.json` |
| `FirmwareForensicsHubView` | **MISSING** | PRESENT | thin mode picker → inspector |
| `FirmwareForensicOrchestrator` | **MISSING** | PRESENT | local analyze → `FirmwareForensicReport` |
| `FirmwareDeepAnalysisMerger` | **MISSING** | PRESENT | merge + `validateServerResult` |
| Local analyzers (`BinaryStatic`, `CryptoAssessor`, `SpeedSignature`, `KnownCFW`, `ComboExtractor`, `ReferenceStore`, `DocumentPicker`) | **MISSING** | PRESENT | Orchestrator deps |
| `DualSourcePanicCard` | **MISSING** | PRESENT | UI only; correlator already on MULTI |
| `FirmwareExportSharePresenter` | PRESENT | **MISSING** | MULTI-only share helper — keep |
| Shared Codable (`DeepAnalysisModels`, `ForensicModels`, `Digest`, `Scorer`, `PDF`, `Briefing`, `ComboPolicy`, `EvidenceTier`, `ReadoutMatch`, `DualSourcePanicCorrelator`) | PRESENT | PRESENT | **identical** across tips |
| `InvestigationStore` / Hub / Detail / CombinedPDF / Models | PRESENT | PRESENT | **identical** (diff size 0) |
| `CrossSourceCorrelator` (+ models / softening / tests) | PRESENT | **MISSING** | MULTI P1-3 — keep |
| `AppSettings.firmwareAnalysisServerURLString` (+ token, allowLLM) | **MISSING** | PRESENT | + `SettingsView` section |
| `Auth/AuthSessionStore` (Bearer JWT) | **MISSING** | PRESENT | hard dep of server submit/poll |
| `FirmwareZipInspectorView` | Legacy ~211 LOC | Forensics ~2208 LOC | MULTI has **no** server/orchestrator path |
| ContentView → `attachFirmwareReport` | **NOT WIRED** | WIRED | MULTI opens legacy sheet w/o callback |

### FirmwareForensics/* file inventory

**On MULTI (11):**  
`DualSourcePanicCorrelator`, `FirmwareComboPolicy`, `FirmwareDeepAnalysisBriefing`, `FirmwareDeepAnalysisModels`, `FirmwareDigest`, `FirmwareEvidenceTier`, `FirmwareExportSharePresenter`, `FirmwareForensicModels`, `FirmwareForensicPDF`, `FirmwareForensicScorer`, `FirmwareReadoutMatchCorrelator`

**UNIFIED-only (13):**  
`DualSourcePanicCard`, `FirmwareBinaryStaticAnalyzer`, `FirmwareComboExtractor`, `FirmwareCryptoAssessor`, `FirmwareDeepAnalysisMerger`, `FirmwareDocumentPicker`, `FirmwareForensicOrchestrator`, `FirmwareForensicsHubView`, `FirmwareKnownCFWCatalog`, `FirmwarePackageLoader`, `FirmwareReferenceStore`, `FirmwareServerAnalysisClient`, `FirmwareSpeedSignatureExtractor`

**MULTI-only (1):** `FirmwareExportSharePresenter`

---

## 2. AppSettings – firmware analysis server URL

| Key / property | MULTI | UNIFIED |
|----------------|-------|---------|
| `firmwareAnalysisServerURLString` | absent | `@Published`, UD key `app.settings.firmware.analysisServerURL.v1` |
| `firmwareAnalysisAPIToken` | absent | UD key `…analysisServerToken.v1` |
| `firmwareAnalysisAllowLLM` | absent | default `false` |
| Default base URL | — | `FirmwareServerAnalysisClient.defaultBaseURLString` = `https://api.tuningscanner.de/scootercheck-fw` |
| Settings UI | none | `SettingsView.firmwareServerSection` (URL + token + LLM toggle) |

MULTI `AppSettings` has no firmware-server fields; grep for `firmwareAnalysis*` under iOS on MULTI is empty outside Integrity copy strings.

---

## 3. Wire points: server job → `FirmwareDeepAnalysisResult` → `InvestigationStore`

End-to-end path on **UNIFIED** (missing as a live path on MULTI):

```
[1] FirmwareDocumentPicker / file Data
        │
        ▼
[2] FirmwarePackageLoader.load(fileName:data:)
        │  inventory + meta
        ▼
[3] FirmwareForensicOrchestrator.analyze(...)
        │  local: Crypto / BinaryStatic / KnownCFW / SpeedSignature
        │  → FirmwareDeepAnalysisMerger.merge(local parts)
        │  → FirmwareForensicReport.deepAnalysis
        ▼
[4] FirmwareZipInspectorView.uploadToAnalysisServer()
        │  FirmwareServerAnalysisClient.fromAppSettings()
        │    ← AppSettings URL/token + AuthSessionStore.shared.token (JWT)
        │  submit(FirmwareAnalysisJobRequest, archiveData)
        │  poll(jobId) until .completed | .failed
        │  status.result: FirmwareDeepAnalysisResult?
        ▼
[5] FirmwareDeepAnalysisMerger.validateServerResult(remote)
        │  (+ coalesceOptionals with existing local deep)
        │  Merger.merge([local, remote])
        │  report.deepAnalysis = merged
        │  report.serverArtifacts = FirmwareServerArtifacts(jobId:, plaintext…, decompile…)
        ▼
[6] onReportProduced?(report, originalData)
        │  FirmwareForensicsHubView forwards same callback
        ▼
[7] ContentView.handleFirmwareReportProduced
        │  ensure activeInvestigationId (create if needed)
        ▼
[8] InvestigationStore.attachFirmwareReport(report, originalData:, to:)
        │  persists firmware-<id>.json via FirmwareForensicPDF.jsonData
        │  InvestigationFirmwareRef.serverJobId ← report.serverArtifacts?.jobId
        │  analysisCompleteness / packageDisplayName / referenceTrust from deepAnalysis
        │  optional archived binary under pack dir
        ▼
[9] setProgress(.showResults) → InvestigationDetailView / CombinedPDF
```

### What MULTI already has for steps 7–9

- `InvestigationStore.attachFirmwareReport` fully implements JSON persist + `serverJobId` + deep metadata fields.
- `InvestigationFirmwareRef.serverJobId` exists.
- `FirmwareForensicReport.deepAnalysis` / `serverArtifacts` Codable types exist (identical).
- Hub creates packs (`startFirmwareOnlyFromHub` → `create(… progress: .selectFirmware)`), then opens **legacy** `FirmwareZipInspectorView()` **without** `onReportProduced` → **store never receives a report**.

### Blocking gaps for steps 1–6

1. No `FirmwarePackageLoader` / `Orchestrator` → cannot build a real `FirmwareForensicReport` on device.  
2. No `FirmwareServerAnalysisClient` + no `AppSettings` URL → cannot submit/poll.  
3. No `AuthSessionStore` → client’s `hasBearerJWT` gate fails even if URL were added (UNIFIED requires Bearer for job ownership).  
4. No modern inspector merge path / HubView.  
5. ContentView must switch sheet → `FirmwareForensicsHubView` + `handleFirmwareReportProduced`.

`CrossSourceCorrelator` (MULTI) is intentionally DTO-stubbed and independent of `FirmwareForensicReport`; wire it later by feeding stubs from readout + zip meta — **not** required for server→store.

---

## 4. Minimal port order (no P0 BLE / Enc2 / WriteGate duplication)

Prefer **file checkout** from UNIFIED over merging the branch. Touch `ContentView` / `BleClient` / Enc2 / WriteGate only with surgical splices. Do **not** take UNIFIED LiveCheck-on-BleClient or radar/auth chrome wholesale.

| Pri | Layer | Checkout / change | Why | Avoid |
|-----|-------|-------------------|-----|-------|
| **P0** | Settings contract | `AppSettings` firmware URL/token/LLM keys + `SettingsView.firmwareServerSection` | Unblocks client config without BLE | Merging entire SettingsView |
| **P1** | Local pipeline | `FirmwarePackageLoader`, `FirmwareCryptoAssessor`, `FirmwareBinaryStaticAnalyzer`, `FirmwareSpeedSignatureExtractor`, `FirmwareKnownCFWCatalog`, `FirmwareComboExtractor`, `FirmwareReferenceStore`, `FirmwareDocumentPicker`, `FirmwareDeepAnalysisMerger`, `FirmwareForensicOrchestrator` + pbxproj | Produces `FirmwareForensicReport` + local `deepAnalysis` offline | Server/auth yet |
| **P2** | Server client | `FirmwareServerAnalysisClient` | Job submit/poll → `FirmwareDeepAnalysisResult` | Admin UI first |
| **P2b** | Auth JWT (minimal) | `AuthSessionStore` (+ Keychain/API as needed) **or** temporary injectable bearer for CI | Client refuses submit without JWT | Full AuthGate / AdminViews unless product requires login UX now |
| **P3** | Inspector + Hub UI | Modern `FirmwareZipInspectorView` (server merge path), `FirmwareForensicsHubView`, optional `DualSourcePanicCard` | Closes upload→validate→merge→callback | Replacing MULTI menu/pedelec chrome |
| **P4** | ContentView wire | Replace legacy sheet with HubView; add `onReportProduced` → `attachFirmwareReport` + progress `.showResults`; keep `activeInvestigationId` | Connects pipeline to existing identical Store | Wholesale ContentView from UNIFIED |
| **P5** | Tests | `FirmwareDeepAnalysisTests` (Merger/Orchestrator/login-required); keep existing Investigation* + CrossSource* tests | Locks merge/validate contracts | Dropping MULTI correlator tests |
| **P6** | Optional later | AdminViews stock/job tools; deepen `CrossSourceCorrelator` from forensic report | Nice-to-have | Not blocking store persistence |

### Explicit non-goals (this port)

- Do **not** re-port Investigation Store/Hub (already identical).  
- Do **not** remove or rewrite `CrossSourceCorrelator` / `FirmwareExportSharePresenter`.  
- Do **not** merge UNIFIED `BleClient` Enc2 / WriteGate / LiveCheck.  
- Do **not** require Ghidra server code in-app — only HTTP client + result Codable (server tree can stay on UNIFIED/server deploy).

---

## 5. Prioritized port list (actionable)

1. **`AppSettings` + Settings UI** — `firmwareAnalysisServerURLString` / API token / allowLLM.  
2. **`FirmwarePackageLoader`** — package inventory foundation.  
3. **Local analyzers + `FirmwareDeepAnalysisMerger` + `FirmwareForensicOrchestrator`** — offline `FirmwareForensicReport`.  
4. **`FirmwareServerAnalysisClient`** — submit/poll → `JobStatus.result`.  
5. **Minimal JWT source** (`AuthSessionStore` or stub) so `hasBearerJWT` works.  
6. **Modern `FirmwareZipInspectorView` server merge** (`validateServerResult` → `report.deepAnalysis` + `serverArtifacts`).  
7. **`FirmwareForensicsHubView`** + DocumentPicker.  
8. **ContentView splice** — Hub cover + `handleFirmwareReportProduced` → `InvestigationStore.attachFirmwareReport`.  
9. **`FirmwareDeepAnalysisTests`** + pbxproj membership for all new files.  
10. **Keep** MULTI `CrossSourceCorrelator` + `FirmwareExportSharePresenter`; optional PanicCard / Admin later.

---

## 6. Return path

**Report path:** `/agent/repos/scootercheck/research/cycle7/agent_d/REPORT_IOS_INTEGRATION.md`

**Checkout source tip for ports:** `origin/cursor/unified-investigation-flow-b100` (`f306bf3`)  
**Apply onto:** `origin/cursor/multi-agent-system-b100` (`f2db879`)  
**Store sink (already present):** `InvestigationStore.attachFirmwareReport(_:originalData:to:)` → `InvestigationFirmwareRef.serverJobId` + packed `FirmwareForensicReport` JSON
