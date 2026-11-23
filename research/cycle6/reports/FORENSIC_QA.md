# Forensic Expert + QA – Cycle 6

## Independent forensic grading

| Claim | Grade | Reason |
|-------|-------|--------|
| A/B are encrypted ZT3 VCU AT32 packs | CONFIRMED | info.json + entropy + member names |
| MD5 integrity of enc payloads | CONFIRMED | matches info.json |
| A and B share 2008-byte enc prefix | CONFIRMED | measured |
| A/B differ in 56288 bytes | CONFIRMED | measured |
| A implements 48 km/h limit | HYPOTHESIS | filename only |
| B is a panic/soft-unlock image | HYPOTHESIS | filename + DualSource heuristic only |
| Button/blinker/BLE state machines mapped | INCOMPLETE | no plaintext |
| Agent consensus alone proves behavior | **rejected** | not used as evidence |

## QA checks

| Check | Result |
|-------|--------|
| File assignment A vs B | PASS (separate dirs + distinct SHA-256) |
| Originals unmodified | PASS (copies only; uploads untouched) |
| Reproducible hashes | PASS (documented in MANIFEST) |
| Alternative explanations present | PASS (in reports) |
| No activation sequences published | PASS |
| Overclaim of Ghidra/disasm | PASS (explicitly unavailable) |

## Corrections applied

- Cycle brief said three files → **two** only (user correction).  
- No REPORT_C.
