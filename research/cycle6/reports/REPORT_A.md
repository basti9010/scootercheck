# REPORT_A – ZT3_VCU_48KMH_5d51.zip

**Cycle 6 · ScooterCheck Firmware Analyst A**  
Stand: 2026-11-23 Europe/Berlin  
Scope: **File A only** · STATIC READ-ONLY  
Arbeitskopie: `research/cycle6/file_a_zt3_vcu_48kmh/`  
Original unter `uploads/` **nicht** verändert.

Epistemik: **CONFIRMED** = gemessen / aus `info.json` gelesen · **HYPOTHESIS** = plausible, unbewiesen · **INCOMPLETE** = mit verfügbaren Mitteln nicht entscheidbar.

---

## 1. Identity

| Feld | Wert |
|------|------|
| Filename label | `ZT3_VCU_48KMH_5d51.zip` |
| Working ZIP | `file_a_zt3_vcu_48kmh/original.zip` |
| ZIP size | 58924 B |
| ZIP SHA-256 | `64d46af6f156ae6a8a09e4b04b80a55fd1aecc16433f839f1d19682f8397bcec` |
| Member `FIRM.bin.enc` | 58504 B |
| Enc SHA-256 | `a5b0e0260989e3c24449ad2d2d82ea2192712183f3145a583e277c6c3af7459d` |
| Enc MD5 | `59857e768098530715639e011bbfa36b` (matches `info.json` → `firmware.md5.enc`) |
| Member `info.json` | 302 B |
| info.json SHA-256 | `a70d73ce1e0de3c76ecd41fde516996d5ef32f7309307200ed5047b1b8f20bc2` |
| Shannon entropy (enc) | ≈ **7.997010** (ciphertext-like) |
| Enc first 16 B | `5716fa528e237b5f6037bc4c65572670` |
| Enc last 16 B | `7fc3633ab906bfc54bc55599c65a4153` |

---

## 2. Format & structure

**CONFIRMED**

| Aspekt | Beobachtung |
|--------|-------------|
| ZIP members | Exactly 2: `FIRM.bin.enc`, `info.json` |
| ZIP timestamps | Both 2026-02-24 12:11 |
| Compression | DEFLATE (method 8); `FIRM.bin.enc` compresses *worse* (58524 > 58504) → consistent with high-entropy ciphertext |
| Payload magic | No ELF / ZIP / gzip container at offset 0; `file`-equivalent: unstructured `data` |
| Size alignment | `58504 % 8 == 0` (compatible with 8-byte block ciphers such as TEA/XTEA used in Ninebot-like packs); `58504 % 16 == 8` (not AES-block-aligned as whole file) |
| Strings | No meaningful ASCII ≥6 (only high-entropy noise collisions) |
| False positives | `MZ` at 57187 and `1f 8b` at 7822 are **not** PE/gzip headers — random ciphertext hits |

### `info.json` schema (CONFIRMED)

```json
{
  "schemaVersion": 1,
  "firmware": {
    "model": "zt3",
    "displayName": "VCU AT32",
    "enforceModel": true,
    "type": "VCU",
    "compatible": ["zt3_VCU_AT32"],
    "encryption": "encrypted",
    "md5": { "enc": "59857e768098530715639e011bbfa36b" }
  }
}
```

No version string, serial, plaintext limit, or build-id fields present.

---

## 3. Processor architecture

| Aussage | Status |
|---------|--------|
| Package targets VCU labeled **AT32** (`displayName`, `compatible: zt3_VCU_AT32`) | **CONFIRMED** (metadata only) |
| Instruction set, vector table, Thumb/ARM opcodes, memory map from payload | **INCOMPLETE** — payload is ciphertext; no plaintext disassembly invented; Ghidra unavailable on this runner |

---

## 4. Metadata findings (CONFIRMED from `info.json`)

| Field | Value | Notes |
|-------|-------|-------|
| `schemaVersion` | `1` | Standard ScooterCheck / Ninebot-like pack schema |
| `model` | `zt3` | Enforceable model token |
| `displayName` | `VCU AT32` | Human label for controller |
| `enforceModel` | `true` | Flasher expected to reject other models |
| `type` | `VCU` | Vehicle Control Unit image |
| `compatible` | `["zt3_VCU_AT32"]` | Compatibility id |
| `encryption` | `encrypted` | Declares ciphertext payload |
| `md5.enc` | `59857e…a36b` | Matches measured MD5 of `FIRM.bin.enc` |

**Not present (CONFIRMED absence):** firmware version, plaintext speed caps, panic/combo fields, BLE MAC, region codes.

**Filename claim (separate):** `48KMH` in `ZT3_VCU_48KMH_5d51.zip` is a **filename label only** → speed-limit **HYPOTHESIS**, not proven by image contents.

---

## 5–12. Research-brief analysis items

| # | Topic | Status | Evidence / reasoning |
|---|-------|--------|----------------------|
| **5** | Config / parameter regions | **INCOMPLETE** | No plaintext config tables, NVM maps, or limit constants recoverable from ciphertext |
| **6** | Event handling | **INCOMPLETE** | No ISR / event-dispatch symbols or handlers visible |
| **7** | State machines | **INCOMPLETE** | No mode/state transition tables or combo FSMs in cleartext |
| **8** | Button input handling | **INCOMPLETE** | No GPIO/button handlers or combo sequences extractable (policy: no decrypt for unlock/activation reconstruction) |
| **9** | Blinker / turn-signal logic | **INCOMPLETE** | No blinker-related strings, timers, or GPIO maps |
| **10** | BLE-related structures | **INCOMPLETE** | Package is VCU-typed; no BLE image or GATT tables inside this ZIP; ciphertext yields no BLE protocol constants |
| **11** | Unusual structures | **HYPOTHESIS** (weak) | Shared 2008-byte identical prefix with File B (same size 58504) suggests common encrypted-pack wrapper; body then diverges (56288 differing bytes). Cause (shared IV/header vs shared cleartext prefix) **INCOMPLETE** without decrypt. Entropy ≈7.997 across file → no low-entropy clear islands |
| **12** | Altered parameters / speed limit | **HYPOTHESIS** | Filename token `48KMH` claims ~48 km/h; **not** confirmed in payload or `info.json`. Stock DE ceiling is typically ~20–22 km/h — elevation would be tuning, but this is unproven here |

Cross-check with File B (context only, not File-B analysis): `info.json` identical except `md5.enc`; both encrypted VCU AT32 packs of equal size — reinforces that A’s differences vs B live in the ciphertext body, not in declared meta.

---

## 6. Findings table

| Filename | SHA-256 | Offset / addr | Observation | Interpretation | Alternative | Confidence |
|----------|---------|---------------|-------------|----------------|-------------|------------|
| `ZT3_VCU_48KMH_5d51.zip` | `64d46af6…7bcec` | ZIP root | 2 members; timestamps 2026-02-24 | Standard encrypted VCU distribution pack | Exotic multi-image ZIP | **high / CONFIRMED** |
| `FIRM.bin.enc` | `a5b0e026…f7459d` | `0..58503` | Entropy ≈7.997; 256 distinct byte values; χ²≈241 vs uniform | Encrypted firmware payload | Compressed-then-encrypted still ciphertext | **high / CONFIRMED** |
| `FIRM.bin.enc` | `a5b0e026…f7459d` | — | Size 58504 ≡ 0 (mod 8) | Consistent with 8-byte block cipher packaging | Coincidence / padded clear length | **medium / HYPOTHESIS** |
| `FIRM.bin.enc` | `a5b0e026…f7459d` | `0` | Header words `0x52fa1657…` — not ARM vector table | Not a loadable AT32 image as-stored | Obfuscated clear header (no evidence) | **high / CONFIRMED** (not vector table) |
| `info.json` | `a70d73ce…f20bc2` | — | `md5.enc` == measured MD5 | Declared integrity check holds | MD5 collision (negligible here) | **high / CONFIRMED** |
| `info.json` | `a70d73ce…f20bc2` | — | `model=zt3`, `type=VCU`, `compatible=zt3_VCU_AT32`, `encryption=encrypted` | Packaged for ZT3 AT32 VCU, encrypted | Mislabeled third-party pack | **high / CONFIRMED** (as metadata) |
| Upload name | — | — | Token `48KMH` | Claimed ~48 km/h tune/limit | Folder/marketing name unrelated to image | **low–medium / HYPOTHESIS** |
| Enc A vs Enc B | — | `0..2007` | 2008 identical prefix bytes; then diverge | Shared pack/cipher framing | Shared cleartext header encrypted under same keystream start | **high / CONFIRMED** (byte equality); cause **INCOMPLETE** |
| Enc A | `a5b0e026…f7459d` | `57187`, `7822` | Spurious `MZ` / `1f8b` | Random ciphertext collisions | Real PE/gzip nested (rejected: context/entropy) | **high / CONFIRMED** (false positive) |

---

## 7. What ScooterCheck modules can already consume

| Module | Usable inputs from File A | Expected behavior |
|--------|---------------------------|-------------------|
| **`DualSourcePanicCorrelator`** | `FirmwareForensicReport` with encrypted crypto status + original filename | Filename does **not** contain `panic`/`softunlock`/`cfw` → no filename-panic hint. Encrypted payload still marks phone side **suspicious** (encrypted ⇒ `phoneOnly` / dual-source patterns when live present). **Cannot** extract button combos from this image offline. |
| **`FirmwareReadoutMatchCorrelator`** | Meta models (`zt3`), type `VCU`, filename tokens `ZT3`/`VCU`, **`claimedKmh` → 48** from `…48KMH…` | With live readout: model/controller checks can match a ZT3 VCU vehicle; speed check can compare filename claim 48 vs live limit/peak (match/mismatch/unclear). Without live context → `inconclusive`. DeepAnalysis speed constants remain empty without decrypt/server. |
| **`InvestigationStore`** | ZIP + SHA-256 + `info.json` meta + forensic report ref | Can archive pack (SHA dedupe), attach report, persist notes / CombinedPDF hooks. Does **not** require plaintext binary. |

Also adjacent (capability inventory): `FirmwareDigest` (hashes), `FirmwareZipInspector` / integrity ZIP path, `FirmwareEvidenceTier` / forensic models — meta + filename hints only. **Not** available on this branch/runner for this analysis: `FirmwarePackageLoader`, `FirmwareBinaryStaticAnalyzer`, `FirmwareServerAnalysisClient`, local Ghidra/`analyzeHeadless`, `binwalk`.

---

## 8. Explicit limitations

1. **Encrypted payload** (`encryption: encrypted`, entropy ≈7.997) — no plaintext ARM/AT32 disassembly; inventing opcodes from ciphertext is banned and was not done.  
2. **No Ghidra** on this runner — no headless decompile, no claimed Ghidra findings.  
3. **No `FirmwarePackageLoader` / server decrypt client** on the multi-agent research branch — offline TEA/XTEA unlock of the image was not performed.  
4. **Policy hard ban** — no decryption aimed at reconstructing activation / unlock / speed-limit bypass sequences.  
5. **`48KMH` is a filename claim only** — not a CONFIRMED installed or coded speed limit.  
6. **No live vehicle readout** in this static pass — DualSource / ReadoutMatch remain meta-/filename-level.  
7. **No OEM stock reference image** in-cycle — cannot classify A as stock vs tuned by binary diff against manufacturer release.  
8. **Originals under `uploads/` untouched**; analysis used working copy only.

---

## Analyst verdict (File A)

Container and metadata are a **CONFIRMED** encrypted Ninebot/Segway-like **ZT3 VCU AT32** pack with integrity-checked ciphertext. All code-level goals (config, events, FSMs, buttons, blinker, BLE, altered params in image) are **INCOMPLETE**. The only speed-related signal is the **HYPOTHESIS** filename claim **48 km/h**.
