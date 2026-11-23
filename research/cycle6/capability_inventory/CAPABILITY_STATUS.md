# Cycle 6 – Capability Inventory

Stand: 2026-11-23 Europe/Berlin  
Branch-Basis: `cursor/multi-agent-system-b100` @ `a2c9329`  
Research-Branch: `cursor/firmware-research-lab-c6-b100`

## CI (vorbereitend)

| Item | Status |
|------|--------|
| PR #103 | offen |
| Run `45245015142` @ `a2c9329` | **in_progress** (Build-for-testing SUCCESS; XCTest running) |
| Letzter P0-Grünlauf | `45239479743` @ `1a0012e` — 324/0 |

## Komponenten – ehrlich

| Komponente | Auf multi-agent vorhanden? | Funktionsfähig für diese Untersuchung? |
|------------|----------------------------|----------------------------------------|
| `FirmwareForensicModels` / Report Codable | JA | JA (Datenmodell) |
| `FirmwareForensicPDF` (+ `jsonData`) | JA | JA (Export) |
| `FirmwareDeepAnalysisModels` (+ Ghidra-Schema-Felder) | JA | Schema only — **kein** lokaler Ghidra-Lauf |
| `FirmwareDigest` | JA | JA (Hashes) |
| `FirmwareEvidenceTier` | JA | JA (Epistemik-Typen) |
| `FirmwareForensicScorer` / `ComboPolicy` / Briefing | JA | Teilweise (ohne Klartext-Binär) |
| `InvestigationStore` / Hub / CombinedPDF | JA | JA (Persistenz/UI) |
| `CrossSourceCorrelator` MVP | JA | JA (DTO-basiert) |
| `FirmwareReadoutMatchCorrelator` | JA | JA (Metadaten/Dateiname ↔ Auslese) |
| `DualSourcePanicCorrelator` | JA | JA (Filename/Encrypt-Heuristik) |
| `FirmwareZipInspectorView` + Integrity ZIP analyzer | JA | JA für ZIP/meta; Enc-Payload begrenzt |
| `FirmwarePackageLoader` | **NEIN** (nicht portiert) | — |
| `FirmwareBinaryStaticAnalyzer` | **NEIN** | — |
| `FirmwareServerAnalysisClient` | **NEIN** | — |
| Lokales Ghidra / `analyzeHeadless` | **NEIN** auf diesem Runner | — |
| `binwalk` | **NEIN** | — |
| `strings` / `python3` / `unzip` / `sha256sum` | JA | JA |

## Konsequenz für Cycle 6

Beide Untersuchungsdateien sind **verschlüsselte** Ninebot/Segway-ähnliche VCU-Pakete (`FIRM.bin.enc` + `info.json`).  
Ohne Entschlüsselung (lokal nicht verfügbar, Server-Client nicht portiert) sind Architektur-, State-Machine-, Tasten-/Blinker-/BLE-Ereignisanalysen auf dem Ciphertext **INCOMPLETE**.  
Erlaubt und belastbar: Container-Metadaten, Integrität (MD5 aus info.json), Entropie, Byte-Diff zwischen A/B, Dateiname-Heuristiken, Integration in vorhandene Correlatoren.
