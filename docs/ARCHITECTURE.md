# ScooterCheck – Architecture

## Schichten (iOS)

```
SwiftUI Screens (ContentView, FAQ, Settings, Find Hub, Radar, Firmware Inspector, …)
        │
        ├── BLEIdentity / Search / Radar / AR (scan + identify + locate)
        ├── Ninebot / Xiaomi / Navee / Pedelec protocol clients (read-only)
        ├── Integrity (FirmwareZipAnalyzer, Stock catalog, CustomFirmwareDiff)
        ├── Evidence / Attribution / Universal Diagnosis
        └── ProtocolHistoryStore + ProtocolPDF (persist + export)
```

## Wichtige Einstiegspunkte

| Komponente | Pfad | Rolle |
|-----------|------|-------|
| App Entry | `ScooterCheckApp.swift` | `@main`, Theme |
| Navigation | `ContentView.swift`, `ScootNavigation.swift` | Screen-Routing / Menü |
| BLE Client | `Ninebot/BleClient.swift` | Enc2/NB Sessions |
| Identify | `BLEIdentity/*` | Hersteller/Modell-Heuristik |
| Find/Radar | `BLESearch*`, `BLEWatchRadar*`, `RadarMap/` | Ortung / Verlauf |
| Firmware ZIP | `Integrity/FirmwareZipAnalyzer.swift`, `FirmwareZipInspectorView.swift` | Read-only ZIP/BIN hints |
| Reports | `ProtocolHistoryStore.swift`, `ProtocolPDF.swift` | Speichern / PDF |
| Design | `Theme.swift`, `ScootDesign.swift` | Dark #12161C, Accent #6BDBC2 |

## Sicherheitsarchitektur

- **Read-only by policy:** keine Limit-Writes, kein Flash, keine Unlock-Ausführung.
- Soft-Unlock-bezogene UI dient der Erkennung/Dokumentation, nicht dem Schreiben.
- Firmware-Dateien = Import-Artefakte, nicht automatisch „installierte Fahrzeug-FW“.

## Investigation Flow (andere Branch-Linie)

Auf `cursor/unified-investigation-flow-b100` existiert ein Hub mit:

- Scooter-only / Firmware-only / Combined guided flow
- `InvestigationStore` + Progress/Resume + Firmware-Archiv (SHA-Dedupe)
- Combined PDF + Identity Guards + Analysis Reuse

Dieser Checkout enthält diese Module **noch nicht**. Merge/Integration ist Roadmap-Thema.

## BLE ↔ Firmware Korrelation (P1-3 Design)

Design-only: `docs/P1-3_BLE_FIRMWARE_CORRELATION.md`.

Geplant als dünner `CrossSourceCorrelator` über bestehende Engines (`BLEIdentity`, `IntegrityReading`/`StockFirmwareCatalog`/`CustomFirmwareDiff`, `FirmwareZipAnalyzer`, `EvidenceEngine`/`AttributionEngine`). Nach Merge der Forensik-Linie: Adapter auf `FirmwareReadoutMatchCorrelator` / `DualSourcePanicCorrelator`. Epistemik: confirmed vs hypothesis; ZIP ≠ installierte FW; kein zweites Verdict.

## Tests

`ios/ScooterCheck/ScooterCheckTests/` – u. a. BLE Identify/Search/Radar, FirmwareZipAnalyzer, Evidence, PDF, Pedelec, Universal Diagnosis, Peak/DIS report bugs.

## Agenten-Rollen vs. Laufzeit

| `.cursor/agents/` | Cloud `Task` subagent_type |
|-------------------|----------------------------|
| project-manager | (Parent / generalPurpose) |
| ios-developer | explore / generalPurpose |
| firmware-analyst | explore / generalPurpose |
| bluetooth-specialist | explore / generalPurpose |
| forensic-expert | explore / generalPurpose |
| ui-ux-designer | explore / generalPurpose |
| qa-security | security-review / explore (readonly) |

Custom agent markdown steuert Cursor-IDE-Agents; Cloud-`Task` nutzt die festen `subagent_type`-Werte und erhält die Spezialistenrolle über den Prompt.
