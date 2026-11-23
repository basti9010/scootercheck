# REPORT_B – ZT3_________panicsystem_9646.zip

Cycle 6 · Firmware Analyst B · 2026-11-23 Europe/Berlin  
**Nur statisch / lesend.** Keine Klartext-Disassembly, keine Aktivierungs-/Unlock-/Speed-Bypass-Rekonstruktion.  
Ghidra / `analyzeHeadless` / `binwalk` / Server-Decrypt: **nicht verfügbar** auf diesem Runner (siehe `capability_inventory/CAPABILITY_STATUS.md`).

## 1. Identität

| Feld | Wert |
|------|------|
| Upload | `ZT3_________panicsystem_9646.zip` |
| Arbeitskopie | `research/cycle6/file_b_zt3_panicsystem/original.zip` |
| ZIP SHA-256 | `6bff28e813c54837d3bb3ac09e8b4721eb75c76529728f0b8c680b4879adbc40` |
| ZIP Größe | 58927 Bytes |
| Mitglieder | `FIRM.bin.enc` (58504), `info.json` (302) |
| Enc SHA-256 | `02e46e8ae98301ee7347d39c539a3df9c973a95ff33481ddfd538adf69472ebc` |
| Enc MD5 | `9235a01f1b022bfe9197ed08739de60a` |
| Enc Entropie (Shannon) | ≈7.996913 |
| Head16 | `5716fa528e237b5f6037bc4c65572670` (byte-identisch mit File A) |
| ZIP-Zeitstempel (Mitglieder) | 2026-03-18 20:33:12 |

Original unter `uploads/` unverändert; Arbeitskopie nicht modifiziert.

## 2. Format & Struktur (CONFIRMED)

- ZIP mit genau zwei Einträgen (`compress_type=8` / deflate); `file(1)`: Zip archive.  
- `info.json` Schema v1, Feld `firmware.encryption = "encrypted"`.  
- `file(1)`: `FIRM.bin.enc` = `data` (kein erkanntes Klartext-Firmware-Image, keine ARM-Vektor-Tabelle am Offset 0).  
- MD5 der Payload stimmt mit `firmware.md5.enc` überein → **Integrität der deklarierten Enc-Checksum CONFIRMED**.  
- Keine sinnvollen ASCII-/UTF-16-Needles (`panic`, `AT32`, `zt3`, `VCU`, `Ninebot`, `km/h`, …) in der Enc-Payload → Klartext-Strings **nicht** beobachtbar.

## 3. Prozessorarchitektur

| Aussage | Status |
|---------|--------|
| Meta: `displayName` „VCU AT32“, `compatible: zt3_VCU_AT32` | CONFIRMED (Metadaten) |
| Instruktionsset / Vektor-Tabelle / Ghidra-Disasm im Binär | **INCOMPLETE** (Ciphertext; Ghidra fehlt) |

## 4. Firmware-Metadaten (CONFIRMED aus info.json)

```json
model: zt3
displayName: VCU AT32
enforceModel: true
type: VCU
compatible: ["zt3_VCU_AT32"]
encryption: encrypted
md5.enc: 9235a01f1b022bfe9197ed08739de60a
```

Alle Felder außer `md5.enc` sind byte-gleich zu File A’s `info.json`.  
Keine Firmware-Versionsstrings, keine Serials, keine Klartext-Limits in info.json.

## 5–12. Analyseziele

| # | Thema | Status | Kurz |
|---|-------|--------|------|
| 5 | Konfigurationsbereiche | INCOMPLETE | nicht im Klartext |
| 6 | Ereignisverarbeitung | INCOMPLETE | — |
| 7 | Zustandsautomaten | INCOMPLETE | — |
| 8 | Tastenereignisse | INCOMPLETE | — |
| 9 | Blinkerereignisse | INCOMPLETE | — |
| 10 | BLE-Ereignisse | INCOMPLETE | — |
| 11 | Auffällige Programmstrukturen | INCOMPLETE | nur Ciphertext-Struktur messbar (hohe Entropie, kein ISA-Header) |
| 12 | Veränderte Parameter / Panic-Claim | HYPOTHESIS | Dateiname enthält `panicsystem`; Payload ≠ A (56288 Diff-Bytes ab Offset 2008) → andere Image-Variante plausibel, **Inhalt/Panic-Verhalten nicht im Klartext belegt** |

**Epistemik zu „panicsystem“:** Nur Filename-Heuristik → **HYPOTHESIS**. Kein Plaintext-Nachweis von Panic-/Reset-/Dual-Source-Logik in dieser Datei.

## Findings-Tabelle

| Datei | SHA-256 (ZIP) | Offset/Addr | Beobachtung | Interpretation | Alternative | Konfidenz |
|-------|---------------|-------------|-------------|----------------|-------------|-----------|
| ZT3_________panicsystem_9646.zip | 6bff28e8…adbc40 | ZIP root | 2 Einträge enc+json | Standard encrypted VCU-Pack | anderes Container-Layout unwahrscheinlich | hoch / CONFIRMED |
| FIRM.bin.enc | 02e46e8a…472ebc | 0..58503 | Entropie ≈7.9969; `file`=data | Verschlüsselte Payload | komprimiert+verschlüsselt | hoch / CONFIRMED |
| info.json | db49e0eb…f1b8c4a | — | md5.enc Match; Meta ≡ A außer MD5 | Checksum korrekt; gleiches Zielmodell | Kollision vernachlässigbar | hoch / CONFIRMED |
| Enc vs A | — | 0..2007 | 2008 Bytes == A | gemeinsamer Wrapper/Crypto-Prefix | Zufall ausgeschlossen bei Länge | hoch / CONFIRMED Diff-Messung |
| Enc vs A | — | 2008..58503 | 56288 Diffs; keine ≥16-Byte-Identitätsläufe danach | andere Ciphertext-Payload (nahezu voll Diff) | Partial-Update / nur Key-Wechsel ohne Inhaltsdiff unwahrscheinlich als Erklärung der Diff-Dichte | hoch / CONFIRMED Diff; Klartext-Ursache INCOMPLETE |
| Dateiname | — | — | Token `panicsystem` | Community-Label Panic/Soft-Unlock / Dual-Source-Kontext | harmloser Ordner-/Paketname ohne Codebezug | niedrig–mittel / HYPOTHESIS |

## ScooterCheck-Hooks

- `DualSourcePanicCorrelator`: `originalFileName.lowercased()` enthält `panic` → `filenamePanicHint` (Code-Kommentar: unverifiziert; Next-Step warnt explizit davor, „Panic“ als bestätigtes Verhalten zu führen).  
- Ohne Live-Auslese: Pattern eher `.phoneOnly` wenn Forensik auffällig (encrypted + filename), nicht `.panicResetSuspected`.  
- `FirmwareDeepAnalysisBriefing.hasFunctionalManipulationEvidence`: Hotword-Liste enthält `panicsystem` (YARA-Familien-/Regel-Match) — hier **kein** YARA-Lauf; Filename allein reicht für ROT nicht.  
- `FirmwareReadoutMatchCorrelator`: Modell-Meta `zt3` / `zt3_VCU_AT32` für Datei↔Auslese-Match nutzbar; kein `claimedKmh` aus diesem Namen.  
- `InvestigationStore` / CombinedPDF: Pack + SHA + info.json archivierbar; Datei ≠ installierte Fahrzeug-FW.  
- `CrossSourceCorrelator`: ohne Live-FW-Strings / Klartext → Versions-Match **incomplete**.  
- Kein Offline-Decrypt / kein Ghidra auf diesem Branch.

## Limitierungen

- Ciphertext → Items 5–11 und ISA-Disassembly **INCOMPLETE**.  
- Ghidra, `FirmwarePackageLoader`, `FirmwareBinaryStaticAnalyzer`, `FirmwareServerAnalysisClient` fehlen lokal.  
- Keine OEM-Referenz, kein Fahrzeugtest, kein rechtmäßiger Schlüssel in diesem Zyklus.  
- Filename `panicsystem` **darf nicht** als bestätigtes Panic-/Dual-Source-Verhalten gelesen werden (nur HYPOTHESIS).
