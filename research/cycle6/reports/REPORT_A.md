# REPORT_A – ZT3_VCU_48KMH_5d51.zip

Cycle 6 · Analyst A / PM synthesis · 2026-11-23 Europe/Berlin  
**Nur statisch / lesend.** Keine Klartext-Disassembly, keine Aktivierungssequenzen.

## 1. Identität

| Feld | Wert |
|------|------|
| Upload | `ZT3_VCU_48KMH_5d51.zip` |
| Arbeitskopie | `research/cycle6/file_a_zt3_vcu_48kmh/original.zip` |
| ZIP SHA-256 | `64d46af6f156ae6a8a09e4b04b80a55fd1aecc16433f839f1d19682f8397bcec` |
| ZIP Größe | 58924 Bytes |
| Mitglieder | `FIRM.bin.enc` (58504), `info.json` (302) |
| Enc SHA-256 | `a5b0e0260989e3c24449ad2d2d82ea2192712183f3145a583e277c6c3af7459d` |
| Enc MD5 | `59857e768098530715639e011bbfa36b` |
| Enc Entropie | ≈7.9970 |
| Head16 | `5716fa528e237b5f6037bc4c65572670` |

Original unter `uploads/` unverändert.

## 2. Format & Struktur (CONFIRMED)

- ZIP mit genau zwei Einträgen; Zeitstempel 2026-02-24.  
- `info.json` Schema v1, Feld `firmware.encryption = "encrypted"`.  
- `file(1)`: `FIRM.bin.enc` = `data` (kein erkanntes Klartext-Image).  
- MD5 der Payload stimmt mit `firmware.md5.enc` überein → **Integrität der deklarierten Enc-Checksum CONFIRMED**.

## 3. Prozessorarchitektur

| Aussage | Status |
|---------|--------|
| Meta: `displayName` „VCU AT32“, `compatible: zt3_VCU_AT32` | CONFIRMED (Metadaten) |
| Instruktionsset / Vektor-Tabelle im Binär | **INCOMPLETE** (Ciphertext) |

## 4. Firmware-Metadaten (CONFIRMED aus info.json)

```json
model: zt3
displayName: VCU AT32
enforceModel: true
type: VCU
compatible: ["zt3_VCU_AT32"]
encryption: encrypted
```

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
| 11 | Auffällige Programmstrukturen | INCOMPLETE | nur Ciphertext-Struktur messbar |
| 12 | Veränderte Parameter | HYPOTHESIS | Dateiname `48KMH` legt Limit-Claim nahe; **nicht** im Image belegt |

## Findings-Tabelle

| Datei | SHA-256 (ZIP) | Offset/Addr | Beobachtung | Interpretation | Alternative | Konfidenz |
|-------|---------------|-------------|-------------|----------------|-------------|-----------|
| ZT3_VCU_48KMH_5d51.zip | 64d46af6…7bcec | ZIP root | 2 Einträge enc+json | Standard encrypted VCU-Pack | anderes Container-Layout unwahrscheinlich | hoch / CONFIRMED |
| FIRM.bin.enc | a5b0e026…f7459d | 0..58503 | Entropie ≈8.0 | Verschlüsselte Payload | komprimiert+verschlüsselt | hoch / CONFIRMED |
| info.json | a70d73ce… | — | md5.enc Match | Checksum korrekt | Kollision vernachlässigbar | hoch / CONFIRMED |
| Dateiname | — | — | Token `48KMH` | Claim „48 km/h“ | Marketing-/Ordnername ohne Bezug | niedrig–mittel / HYPOTHESIS |
| Enc vs B | — | 0..2007 | 2008 Bytes == B | gemeinsamer Wrapper/Prefix | Zufall ausgeschlossen bei Länge | hoch / CONFIRMED Diff-Messung |

## ScooterCheck-Hooks

- `FirmwareReadoutMatchCorrelator.claimedKmh("…48KMH…")` → 48 (Filename claim).  
- `InvestigationStore.attachFirmwareReport` kann Pack + SHA archivieren.  
- `CrossSourceCorrelator`: ohne Live-FW-Strings → incomplete für Versions-Match.  
- Kein Offline-Decrypt auf diesem Branch.

## Limitierungen

Ghidra/Loader/Server-Client fehlen. Keine OEM-Referenz. Keine Fahrzeugtests.
