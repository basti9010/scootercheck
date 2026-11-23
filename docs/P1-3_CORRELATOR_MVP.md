# P1-3 – CrossSourceCorrelator MVP (API)

**Status:** Implemented (compilable MVP)  
**Design:** [`P1-3_BLE_FIRMWARE_CORRELATION.md`](./P1-3_BLE_FIRMWARE_CORRELATION.md)  
**Module:** `ios/ScooterCheck/ScooterCheck/Correlation/`  
**Policy:** Read-only pure functions; no BLE writes; ZIP ≠ installed firmware

---

## Public API

### Epistemics

```swift
enum CorrelationEpistemics: String, Codable, Sendable {
    case confirmed    // label: "Bestätigt"
    case hypothesis   // label: "Hypothese"
    case incomplete   // label: "Unvollständig" — missing sources, never false-confirmed
}
```

### Input DTOs (lightweight; wrap forensic/report types later)

| Type | Role |
|------|------|
| `CorrelationBLEDeviceInfo` | BLE category/confidence/model (`categoryRaw` / `confidenceRaw`) |
| `CorrelationFirmwareVersions` | `fwVcu` / `fwMcu` / `fwBle` / … dump strings |
| `CorrelationDeviceIdTraits` | profile/model labels, peripheral id |
| `CorrelationZipMeta` | ZIP displayName, models, boards, MD5/size, finding stubs |
| `CorrelationForensicSummaryStub` | optional live digest / stock-diff note (no full report) |
| `CrossSourceSnapshot` | composition of the above |

### Output

```swift
struct CorrelationItem { id, kind, epistemics, title, detail, sources, confidence }
struct SoftenedZipFinding { … confidence, epistemics, annotation? }
struct CrossSourceAssessment {
    items, summary, caveats, softZipFindings, attributionHints
    // helpers: confirmedItems / hypothesisItems / incompleteItems
}
```

### Correlator

```swift
enum CrossSourceCorrelator {
    static func assess(_ snapshot: CrossSourceSnapshot) -> CrossSourceAssessment
}
```

MVP checks: `modelFamily`, `firmwareVersion`, `imageDigestHint`.

### Softening

```swift
enum ZipFindingSoftening {
    static func soften(_ findings: [CorrelationZipFindingInput]) -> [SoftenedZipFinding]
    static func softenOne(_ finding: CorrelationZipFindingInput) -> SoftenedZipFinding
}
```

Generic needles (`power button`, `mode button`, lone `km/h`) → confidence `.low` + hypothesis annotation. Findings are demoted, never deleted.

---

## Confirmation rules (MVP)

| Kind | Confirmed when | Else |
|------|----------------|------|
| `firmwareVersion` | Dump version token (e.g. `1.5.8`) with boundaries in ZIP text | fuzzy digits → hypothesis; mismatch → hypothesis; missing side → **incomplete** |
| `modelFamily` | ZIP∩device tokens **and** BLE `eScooter` medium+ | ZIP-only → hypothesis; missing → incomplete |
| `imageDigestHint` | — (never “installed”) | MD5/size alone → hypothesis + caveat |

Hard rule: MD5/size of an imported file never becomes confirmed installation.

---

## Tests

`ScooterCheckTests/CrossSourceCorrelatorTests.swift` — match / mismatch / missing / model / digest / softening / labels.

---

## Deferred (not in this MVP)

- UI in `FirmwareZipInspectorView` / PDF appendix
- Adapters from `IntegrityReading`, `FirmwareZipReport`, `BLEIdentificationResult`
- `FirmwareReadoutMatchCorrelator` / `DualSourcePanicCorrelator` merge
- AttributionAlign, speedPicture, customFirmwareHint cross-source
- ContentView / BleClient changes (explicitly out of scope)
