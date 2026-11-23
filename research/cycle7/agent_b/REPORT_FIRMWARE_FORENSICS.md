# REPORT_FIRMWARE_FORENSICS – Cycle 7 AGENT B

**Cycle:** 7 · Server Firmware Analysis & Intelligent Orchestration  
**Agent:** B – Firmware Forensics (static re-verify of Cycle-6 packs)  
**Stand:** 2026-11-23 Europe/Berlin  
**Inputs:** Cycle-6 ZIPs (uploads + `research/cycle6/` / `C6_MANIFEST_REF.md`)  
**Scope:** STATIC READ-ONLY · no decrypt · no Ghidra on ciphertext · no unlock/activation reconstruction

Epistemik: **CONFIRMED** = gemessen / aus `info.json` · **HYPOTHESIS** = Dateiname/Heuristik · **INCOMPLETE** = Klartext/ISA/FSM nicht entscheidbar.

---

## 0. Subject packs

| ID | Upload-Name | ZIP SHA-256 | ZIP size |
|----|-------------|------------|----------|
| **A** | `ZT3_VCU_48KMH_5d51.zip` | `64d46af6f156ae6a8a09e4b04b80a55fd1aecc16433f839f1d19682f8397bcec` | 58924 B |
| **B** | `ZT3_________panicsystem_9646.zip` | `6bff28e813c54837d3bb3ac09e8b4721eb75c76529728f0b8c680b4879adbc40` | 58927 B |

Hashes **re-confirmed** against uploads on this runner (match Cycle-6 `MANIFEST_SHA256.txt` / `C6_MANIFEST_REF.md`).

---

## 1. Container

**CONFIRMED** for both A and B:

| Aspekt | A | B |
|--------|---|---|
| Format | ZIP (DEFLATE / method 8) | same |
| Members | exactly 2: `FIRM.bin.enc`, `info.json` | same |
| Member timestamps | 2026-02-24 12:11:50 | 2026-03-18 20:33:12 |
| `FIRM.bin.enc` size | 58504 | 58504 |
| `info.json` size | 302 | 302 |
| Enc compress ratio | compressed size > raw (ciphertext-like) | same pattern |

No nested ZIP/ELF/gzip container at payload offset 0. Spurious `MZ` / `1f 8b` hits in ciphertext are false positives (Cycle-6 REPORT_A; re-verified structure only).

---

## 2. Integrity

| Check | A | B | Grade |
|-------|---|---|-------|
| ZIP SHA-256 matches Cycle-6 manifest | yes | yes | **CONFIRMED** |
| MD5(`FIRM.bin.enc`) == `info.json` → `firmware.md5.enc` | `59857e768098530715639e011bbfa36b` | `9235a01f1b022bfe9197ed08739de60a` | **CONFIRMED** |
| Enc SHA-256 | `a5b0e026…f7459d` | `02e46e8a…472ebc` | **CONFIRMED** |
| info.json SHA-256 | `a70d73ce…f20bc2` | `db49e0eb…f1b8c4a` | **CONFIRMED** |

Integrity of declared encrypted payloads holds. No evidence of ZIP corruption or mismatched metadata checksums.

---

## 3. Metadata (`info.json`)

Both packs share schema v1 and identical fields except `md5.enc`:

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
    "md5": { "enc": "<per-pack>" }
  }
}
```

**CONFIRMED (metadata):** target model `zt3`, type `VCU`, compatible `zt3_VCU_AT32`, encryption declared.  
**CONFIRMED absence:** firmware version, serial, plaintext speed caps, panic/combo fields, BLE MAC, region codes, build-id.

---

## 4. Encryption status

| Messung | A | B | Grade |
|---------|---|---|-------|
| `encryption` field | `encrypted` | `encrypted` | **CONFIRMED** |
| Shannon entropy | ≈7.997010 | ≈7.996913 | **CONFIRMED** (ciphertext-like) |
| Head16 | `5716fa528e237b5f6037bc4c65572670` | identical | **CONFIRMED** |
| Size alignment | `58504 % 8 == 0`; `% 16 == 8` | same | compatible with 8-byte block packaging (**HYPOTHESIS** for TEA/XTEA; not proven) |
| ARM/AT32 vector table at offset 0 | absent | absent | **CONFIRMED** (not a loadable clear image as-stored) |
| Meaningful ASCII ≥6 in payload | none | none | **CONFIRMED** |

**Verdict:** both members are **encrypted VCU packs**. Offline plaintext analysis is blocked.

---

## 5. Binary diffs (A vs B)

| Messung | Wert | Grade |
|---------|------|-------|
| `identical` | `false` | **CONFIRMED** |
| Identical prefix | **2008** bytes | **CONFIRMED** |
| Differing bytes | **56288** / 58504 | **CONFIRMED** |
| Max identical run after first diff | 1 byte | **CONFIRMED** |
| Identical suffix | 0 | **CONFIRMED** |

**Interpretation (CONFIRMED measurement / INCOMPLETE cause):** shared encrypted-pack framing or cipher prefix for 2008 bytes; thereafter near-full ciphertext divergence → distinct image variants. Whether the shared prefix is a common cleartext header under the same keystream start vs a fixed wrapper remains **INCOMPLETE** without authorized decrypt.

---

## 6. Existing Cycle-6 analysis results (carried forward)

Sources: `research/cycle6/reports/REPORT_A.md`, `REPORT_B.md`, `COMPARATIVE_ANALYSIS.md`, `FORENSIC_QA.md`, `capability_inventory/CAPABILITY_STATUS.md`.

| Claim | Grade | Notes |
|-------|-------|-------|
| A/B = encrypted ZT3 VCU AT32 packs | **CONFIRMED** | re-verified Cycle 7 |
| MD5 integrity | **CONFIRMED** | re-verified |
| 2008-byte shared enc prefix + 56288 diffs | **CONFIRMED** | re-verified |
| A implements 48 km/h | **HYPOTHESIS** | filename token `48KMH` only |
| B is panic/soft-unlock image | **HYPOTHESIS** | filename token `panicsystem` only |
| Agent consensus alone proves behavior | **rejected** | FORENSIC_QA |

Cycle-6 capability inventory: local Ghidra / PackageLoader / ServerAnalysisClient were absent on the multi-agent research branch for that lab. Cycle 7 may port server/iOS clients separately — **this report does not treat ciphertext as decryptable on-device**.

---

## 7. Plaintext / ISA / FSM — **INCOMPLETE**

| Topic | Status | Reason |
|-------|--------|--------|
| Plaintext firmware image | **INCOMPLETE** | ciphertext only |
| Instruction set / Thumb/ARM opcodes / IVT | **INCOMPLETE** | no clear load image; Ghidra on enc forbidden |
| Config / parameter regions | **INCOMPLETE** | — |
| Event handling / ISRs | **INCOMPLETE** | — |
| State machines (mode/combo FSM) | **INCOMPLETE** | — |
| Button / blinker / BLE handlers in image | **INCOMPLETE** | — |
| Speed-limit constants in code | **INCOMPLETE** | DeepAnalysis speed fields empty without decrypt |

**Do not invent opcodes, FSMs, or combo sequences from ciphertext.**

---

## 8. Filename claims — **HYPOTHESIS** only

| Pack | Token | Claim | Grade |
|------|-------|-------|-------|
| A | `48KMH` | ~48 km/h tune/limit | **HYPOTHESIS** — not in `info.json` or payload |
| B | `panicsystem` | panic / soft-unlock / dual-source community label | **HYPOTHESIS** — no plaintext proof |

These labels are useful as **filename heuristics** for correlators; they are **not** confirmed installed behavior.

---

## 9. ScooterCheck correlator hooks

### `DualSourcePanicCorrelator`

Code path: `originalFileName.lowercased()` contains `panic` / `softunlock` / `cfw` → `filenamePanicHint`; encrypted crypto status marks phone side suspicious.

| Pack | Expected static phone signals (no live readout) |
|------|--------------------------------------------------|
| A (`…48KMH…`) | Encrypted → suspicious; **no** filename panic hint → pattern typically **`.phoneOnly`** if forensic alone |
| B (`…panicsystem…`) | Encrypted + **`filenamePanicHint=true`** → still **`.phoneOnly`** without live; **`.panicResetSuspected`** only when phone suspicious **and** live looks stock |

Caveats already in correlator: filename panic is unverified; encrypted images do not yield combos; file ≠ proven flashed image.

`FirmwareDeepAnalysisBriefing` hotwords include `panicsystem` — filename/YARA-family hint only; **not** ROT without live/clear evidence.

### `FirmwareReadoutMatchCorrelator`

| Pack | Usable inputs | Without live |
|------|---------------|--------------|
| A | Meta `zt3` / type `VCU` / name tokens `ZT3`/`VCU`; **`claimedKmh` → 48** via `(\d{2,3})[-_]?kmh` | Verdict **`.inconclusive`** |
| B | Meta `zt3` / `VCU` / `ZT3`; **no** `claimedKmh` | **`.inconclusive`** |

With live ZT3 VCU readout: model/controller checks can match; A's speed check can compare filename 48 vs live limit/peak (match/mismatch/unclear). DeepAnalysis code speeds remain empty until authorized server decrypt.

### Adjacent

- `InvestigationStore` / CombinedPDF: archive both packs by SHA + `info.json` + forensic report refs (no plaintext required).  
- `CrossSourceCorrelator`: no FW version in meta → version match stays incomplete.  
- `FirmwareZipInspector` / Digest: container + integrity path already sufficient for L0–L3 lab work.

---

## 10. Recommendation (Cycle-7 policy)

**Encrypted packs must stay non-Ghidra until authorized decrypt on server.**

1. Local / CI / Agent runners: treat `FIRM.bin.enc` as opaque — hashes, entropy, meta, filename heuristics, byte-diff only.  
2. Do **not** feed ciphertext to Ghidra/`analyzeHeadless`/Capstone/angr; results would be meaningless or fabricate false ISA findings.  
3. Decrypt only via gated **server** job (`FirmwareServerAnalysisClient` / `server/firmware-analysis`) with lawful keys, auth, and explicit user/policy approval.  
4. After server returns plaintext (or structured DeepAnalysis), then optionally schedule Ghidra — never reverse that order for these ZT3 packs.  
5. Keep correlator outputs tagged: filename `48KMH` / `panicsystem` = **HYPOTHESIS**; plaintext/ISA/FSM = **INCOMPLETE** until decrypt completes.

---

## 11. Analyst verdict

Both Cycle-6 subjects are **CONFIRMED** encrypted Ninebot/Segway-like **ZT3 VCU AT32** distribution packs with matching MD5 metadata, high-entropy payloads, a shared 2008-byte ciphertext prefix, and 56288 differing body bytes. All code-level goals remain **INCOMPLETE**. Filename tokens `48KMH` and `panicsystem` remain **HYPOTHESIS** hooks for `FirmwareReadoutMatchCorrelator` / `DualSourcePanicCorrelator`, not proven vehicle behavior. **No local Ghidra until authorized server decrypt.**
