# P1-3 – BLE ↔ Firmware Correlation Architecture

**Status:** Design + MVP correlator — see `P1-3_CORRELATOR_MVP.md` (Cycle 5 P1-3)  
**Branch intent:** Reuse engines; no second Evidence/Attribution/ZIP analyzer  
**Policy:** Read-only; no vehicle writes; ZIP ≠ installed firmware

---

## Problem

Four evidence planes exist today but are only weakly linked in this checkout:

| Plane | Existing module (this checkout) | Sibling branch (not merged here) |
|-------|----------------------------------|----------------------------------|
| BLE identity / fingerprint | `BLEIdentity/*`, `BLEDeviceFingerprint` | — |
| Live dump FW versions | `IntegrityReading.fw*`, `StockFirmwareCatalog`, `CustomFirmwareDiff` | `InvestigationReadoutSummary` |
| Firmware ZIP analysis | `FirmwareZipAnalyzer` → `FirmwareZipReport` | `FirmwareForensicOrchestrator` → `FirmwareForensicReport` |
| Forensic / attribution | `EvidenceEngine`, `AttributionEngine` | `DualSourcePanicCorrelator`, `FirmwareReadoutMatchCorrelator`, `FirmwareEvidenceTier` |

Roadmap ask: optional **MD5/size hints** between ZIP and BLE dump; soften string heuristics; distinguish **confirmed** vs **hypothesis**; never claim the imported file is flashed.

---

## Design principles

1. **Adapter, not engine** — one pure correlator consumes outputs of existing analyzers; does not re-parse ZIPs or re-run Evidence/Attribution.
2. **Epistemic split** — every correlation item is either `confirmed` (cross-source agreement with hard anchors) or `hypothesis` (single-source / string / heuristic).
3. **ZIP ≠ vehicle** — file findings never raise the main integrity verdict alone; they may only annotate or feed attribution *after* Evidence.
4. **No manipulation** — correlator is offline/pure; UI stays document-picker + display; `BleWriteGate` unchanged.
5. **Prefer sibling correlators** — when Investigation Flow / FirmwareForensics merge (`cursor/unified-investigation-flow-b100`), wrap/extend `FirmwareReadoutMatchCorrelator` + `DualSourcePanicCorrelator` instead of inventing a third stack.

---

## Proposed types / modules

### New (thin layer)

```
Integrity/Correlation/   // or Investigation/ after P1-1 merge
  CrossSourceSnapshot.swift      // inputs only (refs + immutable copies)
  CrossSourceCorrelator.swift    // pure assess()
  CrossSourceAssessment.swift    // output model
  ZipFindingSoftening.swift      // maps FirmwareZipReport.Finding → softened confidence
```

Optional later (post P1-1): thin facade that calls remote `FirmwareReadoutMatchCorrelator.assess` and maps into `CrossSourceAssessment`.

### Core types

```swift
enum CorrelationEpistemics: String, Codable, Sendable {
    case confirmed   // multi-source hard anchor agreement
    case hypothesis  // single-source, string, or soft match
}

enum CorrelationKind: String, Codable, Sendable {
    case deviceIdentity      // BLE id / fingerprint ↔ readout peripheral
    case modelFamily         // identify/profile ↔ ZIP models / boards
    case firmwareVersion     // dump fwVcu/Mcu/Ble ↔ ZIP meta / name tokens
    case imageDigestHint     // MD5 / byte size (never “installed”)
    case speedPicture        // dump limits/peak ↔ ZIP speed strings / params
    case customFirmwareHint  // CustomFirmwareDiff ↔ ZIP custom signatures
    case attributionAlign    // AttributionAssessment ↔ ZIP / dual-source pattern
}

struct CorrelationItem: Identifiable, Codable, Sendable {
    var id: String
    var kind: CorrelationKind
    var epistemics: CorrelationEpistemics
    var title: String
    var detail: String
    var sources: [CorrelationSourceRef]  // bleIdentity | dump | zip | evidence | attribution
    var confidence: FirmwareZipReport.Finding.Confidence  // reuse existing enum
}

struct CrossSourceAssessment: Codable, Sendable {
    var items: [CorrelationItem]
    var summary: String
    var caveats: [String]                 // always include ZIP≠installed
    var softZipFindings: [SoftenedZipFinding]
    /// Never feeds EvidenceEngine.verdict. Optional side channel only.
    var attributionHints: [String]
}

struct CrossSourceSnapshot: Sendable {
    var bleIdentity: BLEIdentificationResult?
    var fingerprint: BLEDeviceFingerprint?
    var peripheralId: UUID?
    var reading: IntegrityReading?
    var profile: ScooterProfile?
    var evidence: EvidenceAssessment?     // read-only; attribution optional
    var zipReport: FirmwareZipReport?     // this checkout MVP
    // After forensics merge:
    // var forensicReport: FirmwareForensicReport?
}
```

### Explicit non-goals for this module

- No new `CBCentralManager`, no GATT writes, no flash, no unlock execution.
- No duplication of `StockFirmwareCatalog.analyze`, `CustomFirmwareDiff`, `AttributionEngine`, `FirmwareZipAnalyzer`.
- No elevation of ZIP string hits to Evidence `starkerHinweis`.

---

## Data flow

```
BLE scan
  └─ BLEIdentificationEngine / BLEDeviceFingerprint
         │
BLE readout (read-only)
  └─ IntegrityReading + StockFirmwareCatalog + CustomFirmwareDiff
         └─ EvidenceEngine → EvidenceAssessment (+ AttributionEngine after)
                │
User picks ZIP (existing FirmwareZipInspector / Investigation firmware step)
  └─ FirmwareZipAnalyzer.analyze → FirmwareZipReport
         │
         ▼
CrossSourceCorrelator.assess(snapshot)   // pure, sync
         │
         ├─ confirmed items (e.g. model token match + profile agreement)
         ├─ hypotheses (string unlock, soft MD5 without live hash, alone)
         └─ softened ZIP findings (confidence floor for short/generic needles)
                │
                ▼
UI / PDF annotation section  — does NOT rewrite Evidence.verdict
```

### Confirmation rules (examples)

| Claim | Confirmed when | Else |
|-------|----------------|------|
| Same device lineage | `blePeripheralId` matches history + fingerprint medium/high | hypothesis / missing |
| Model family aligns | ZIP `models`/`compatible` ∩ profile/modelLabel with normalized tokens **and** BLE category eScooter medium+ | hypothesis if ZIP-only or name-only |
| FW version aligns | dump `fwVcu`/`fwMcu`/`fwBle` exact/normalized token in ZIP `displayName` or `info.json` | hypothesis if digits-only fuzzy |
| Image digest hint | ZIP `computedMd5`/`firmSizeBytes` present **and** (future) forensic digest equal; still **not** “installed” | always caveat; alone = hypothesis |
| Custom FW | `CustomFirmwareDiff.level == .confirmed` **and** ZIP `.customFirmware` high | either alone = hypothesis for cross-source |
| Attribution method | `AttributionAssessment.isDeterminate` **and** ZIP/dual-source pattern agrees | attribution remains heuristic label |

Hard rule: **MD5/size match of an imported file never becomes `confirmed` installation.** At most `confirmed` *file integrity* (declared vs computed MD5 inside the ZIP — already in `FirmwareZipReport.md5Matches`).

---

## Soften ZIP string heuristics (no second engine)

Keep `FirmwareZipAnalyzer.scanBinaryHeuristics` as source of truth; add a **post-pass** `ZipFindingSoftening`:

- Generic needles (`power button`, `mode button`, lone `km/h`) → force `confidence = .low` + `epistemics = .hypothesis`.
- Require min needle length / word-boundary for medium+.
- Unlock/gesture strings remain displayable but labeled **Datei-Hinweis — am Fahrzeug unbestätigt** unless a live dump marker supports the same theme (e.g. session-clear power-cycle + elevated limit) → then still hypothesis for *method*, only stronger supporting text.
- Do not delete findings; demote and annotate so PDF/UI stay conservative.

---

## UI plug-in points

| Surface (this checkout) | Hook |
|-------------------------|------|
| `FirmwareZipInspectorView` | After ZIP analyze: if `ProtocolHistoryStore` has a recent/selected readout, show “Abgleich mit letzter Auslese” section (`CrossSourceAssessment`). |
| Report detail in `ContentView` (~evidence / attribution block) | Optional “Querverweise Datei↔Auslese” under attribution; never above verdict. |
| `ProtocolPDF` | New appendix subsection: correlation items split Confirmed / Hypotheses + fixed caveats. |
| BLE device analysis | Optional “Link ZIP…” only as navigation to inspector with peripheralId prefilled in snapshot — no new BLE ops. |

| After P1-1 Investigation merge | Hook |
|--------------------------------|------|
| Combined results step | Prefer existing `FirmwareReadoutMatchCorrelator` + `DualSourcePanicCard`; map into same `CrossSourceAssessment` for one UI language. |
| `InvestigationStore` | Persist assessment JSON next to firmware ref (recompute on resume if stale). |

---

## First MVP slice (smallest shippable)

**Scope:** this checkout only — no forensics stack merge required.

1. `CrossSourceSnapshot` builder from:
   - last / selected `ProtocolHistoryStore` entry (`IntegrityReading`, `blePeripheralId`, profile),
   - optional cached `BLEIdentificationResult` for that peripheral,
   - current `FirmwareZipReport`.
2. `CrossSourceCorrelator.assess` with three check kinds only:
   - `modelFamily`
   - `firmwareVersion` (token vs `fwVcu`/`fwMcu`/`fwBle`)
   - `imageDigestHint` (show ZIP MD5 + size; status `hypothesis` / informational — “kein Live-Image-Hash verfügbar”)
3. `ZipFindingSoftening` applied when rendering ZIP findings in inspector.
4. UI: one section in `FirmwareZipInspectorView` + caveats; PDF deferred to slice 2.

**Out of MVP:** AttributionAlign, DualSource panic, forensic SHA stock-diff, Investigation hub wiring.

---

## Reuse map (do not duplicate)

| Need | Call |
|------|------|
| Identify / confidence | `BLEIdentificationEngine` / cached `BLEIdentificationResult` |
| Fingerprint compare | `BLEFingerprintService.compare` |
| Dump FW vs stock | `StockFirmwareCatalog.analyze` |
| Custom vs stock dump | `CustomFirmwareDiff.analyze` |
| Main verdict | `EvidenceEngine` only |
| Method guess | `AttributionEngine.assess` (already detached) |
| ZIP parse | `FirmwareZipAnalyzer.analyze` |
| File↔readout (post-merge) | `FirmwareReadoutMatchCorrelator.assess` |
| Panic dual-source (post-merge) | `DualSourcePanicCorrelator.assess` |
| Evidence tiers (post-merge) | `FirmwareEvidenceTier` for labeling only |

---

## Test ideas

Unit tests only (pure correlator + softening) — `ScooterCheckTests/CrossSourceCorrelatorTests.swift`:

1. **No readout** → all checks missing/inconclusive; caveats include ZIP≠installed.
2. **Model match confirmed** — ZIP models `["G3"]`, profile Max G3 / modelLabel contains G3, BLE eScooter medium+ → `modelFamily` confirmed.
3. **Model ZIP-only** — no reading → hypothesis or missing, never confirmed.
4. **Version token match** — `fwVcu = "1.5.8"`, ZIP displayName contains `1.5.8` → `firmwareVersion` confirmed; digit-only `158` fuzzy → hypothesis.
5. **MD5 alone** — computed MD5 present, no live hash → `imageDigestHint` hypothesis + caveat; does not create Evidence markers.
6. **Softening** — finding with needle `power button` demoted to low/hypothesis; `ScooterHacking` custom signature stays high but still file-plane.
7. **Verdict isolation** — given stock `EvidenceAssessment`, correlator output must not change `verdict` / `score` (smoke: assess evidence before/after attaching correlation).
8. **Write policy** — correlator symbols must not reference `BleClient` write APIs (static review / existing `WriteDisableRegressionTests` unchanged).
9. **Post-merge adapter** — when forensics present: map `FirmwareReadoutMatchCorrelator.Assessment` checks into `CorrelationItem` without double-counting mismatches.

Fixtures: reuse `Analyzer` demo readings + synthetic `FirmwareZipReport` (no real binaries required for MVP tests).

---

## Integration order vs other P1 items

1. **P1-1** Investigation Flow gap/merge — preferred long-term host for correlation UI.
2. **P1-3** (this) — design + MVP correlator can land against ZIP inspector first.
3. **P1-2** ContentView shell — keep correlation out of the god-object; prefer inspector / investigation detail.
4. **P1-4** Regression — lock softening + verdict isolation tests.

---

## Open decisions (non-blocking for MVP)

- Persist correlation into `ProtocolHistoryStore` vs recompute on open.
- Whether softened ZIP findings mutate `FirmwareZipReport` in place or only at display boundary (prefer display boundary to keep analyzer deterministic).
- Exact merge strategy with `FirmwareReadoutMatchCorrelator` once P1-1 lands (adapter vs rename).
