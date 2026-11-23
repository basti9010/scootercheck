# COMPARATIVE_ANALYSIS – Cycle 6 (zwei Dateien)

Stand: 2026-11-23 Europe/Berlin  
Scope: **Datei A** (`ZT3_VCU_48KMH_5d51.zip`) vs **Datei B** (`ZT3_________panicsystem_9646.zip`)  
Kein File C.

## Epistemik

Nur **CONFIRMED** aus Messungen/Metadaten; Dateiname-Claims = **HYPOTHESIS**; Klartext-Disassembly = **INCOMPLETE** (verschlüsselt, kein Ghidra/Loader).

## Container-Gemeinsamkeiten (CONFIRMED)

| Merkmal | A | B |
|---------|---|---|
| ZIP-Mitglieder | `FIRM.bin.enc` + `info.json` | identisch strukturiert |
| Enc-Größe | 58504 | 58504 |
| info.json schemaVersion | 1 | 1 |
| model | `zt3` | `zt3` |
| displayName | `VCU AT32` | `VCU AT32` |
| type | `VCU` | `VCU` |
| compatible | `zt3_VCU_AT32` | `zt3_VCU_AT32` |
| encryption | `encrypted` | `encrypted` |
| MD5(enc) == info.json | ja | ja |
| Shannon-Entropie enc | ≈7.997 | ≈7.997 |

Interpretation: Beide sind **dasselbe Paketformat** (Ninebot/Segway-ähnliches encrypted VCU-Image für ZT3 / AT32-VCU).  
Alternative: Display-Name „AT32“ ist Hersteller-Meta und beweist allein keine MCU-Instruktionen im Ciphertext (bleibt Meta-CONFIRMED, ISA-INCOMPLETE).

## Payload-Differenzen (CONFIRMED)

| Messung | Wert |
|---------|------|
| ZIP SHA-256 | verschieden |
| Enc SHA-256 / MD5 | verschieden |
| Identischer Prefix | **2008** Bytes identisch |
| Abweichende Bytes | **56288** / 58504 |
| Identischer Suffix | 0 |

Interpretation: Gemeinsamer Header/Wrapper oder gemeinsame Cipher-Struktur über die ersten 2008 Bytes; danach unterschiedliche Ciphertexte (andere Keys/IV/Inhalt).  
Alternative: Blockverschlüsselung mit gemeinsamem Prefix ohne inhaltliche Gleichheit des Klartexts.  
Konfidenz Prefix-Messung: **hoch (CONFIRMED)**; Klartext-Ursache: **INCOMPLETE**.

## Dateiname-Claims (HYPOTHESIS only)

| Datei | Claim im Namen | App-Hook |
|-------|----------------|----------|
| A | `48KMH` | `FirmwareReadoutMatchCorrelator.claimedKmh` kann 48 aus dem Namen lesen — **nicht** als installiertes Limit bestätigt |
| B | `panicsystem` | `DualSourcePanicCorrelator` / Briefing-Hotwords flaggen Filename — **nicht** als bestätigtes Panic-Verhalten |

## Ereignisverarbeitung / State Machines / Tasten / Blinker / BLE

| Thema | A | B | Vergleich |
|-------|---|---|-----------|
| Konfigurationsregionen im Klartext | INCOMPLETE | INCOMPLETE | kein Diff möglich |
| Ereignisverarbeitung | INCOMPLETE | INCOMPLETE | — |
| Zustandsautomaten | INCOMPLETE | INCOMPLETE | — |
| Tasten / Blinker / BLE-Handler | INCOMPLETE | INCOMPLETE | — |

Begründung: Payload ist Ciphertext; lokale Entschlüsselung und Ghidra fehlen auf diesem Branch/Runner.

## Hersteller-/Seriennähe

- Beide deklarieren **seriennahe** Zielhardware (`zt3` / `VCU AT32`) — CONFIRMED Meta.  
- Ob Images Stock, CFW oder Panic-Variante sind, ist aus dem Ciphertext **nicht** CONFIRMED.  
- Referenz-Stock-Image: **nicht** in dieser Untersuchung vorhanden → kein Binär-Diff gegen OEM (nicht erfunden).

## ScooterCheck-Relevanz

1. InvestigationStore kann beide Packs als Firmware-Refs archivieren (SHA + info.json).  
2. CrossSourceCorrelator: FW-Versionen fehlen in info.json → eher `incomplete` für Versions-Match.  
3. DualSourcePanic: B liefert Filename-Panic-Hint; A liefert Limit-Claim 48 — beide Heuristiken, Live-Auslese nötig für Pattern `panicResetSuspected` / Speed-Check.  
4. Ohne Server-Decrypt bleibt DeepAnalysis Combo/Limit-Region leer.

## Offene technische Blocker

- Kein `FirmwarePackageLoader` / `FirmwareServerAnalysisClient` / `FirmwareBinaryStaticAnalyzer` auf multi-agent  
- Kein Ghidra Headless auf Runner  
- Rechtmäßige Schlüssel nicht in diesem Zyklus verwendet (Policy)
