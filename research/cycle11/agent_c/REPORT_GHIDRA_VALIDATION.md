# Cycle 11 Agent C — Ghidra Validation (Diagnostics Selftest)

**Role:** GHIDRA VALIDATION  
**Date:** 2026-11-23 (UTC)  
**Base:** `cursor/server-diagnostics-c11-b100` @ `9c6b153`  
**Branch:** `cursor/ghidra-validation-c11-b100`  
**Subject:** synthetic Cortex-M Thumb only (`SYNTH_C7_NOT_SCOOTER_FW`) — **no** real encrypted ZT3 plaintext

---

## Epistemic grades

| Grade | Verdict | Rationale |
|-------|---------|-----------|
| **CONFIGURED** | **NO** | `GHIDRA_HOME` / `GHIDRA_HEADLESS` unset; `analyzeHeadless` unresolved |
| **AVAILABLE** | **NO** | No executable `analyzeHeadless` on PATH or under `/opt/ghidra` |
| **VERIFIED** | **NO** | Import → analyze → functions/CFG export path **not** executed |
| **FAILED** | **YES (overall)** | Step 1 = `FAILED` + `MISSING_PREREQUISITE`; steps 2–6 = `UNKNOWN` |
| **UNKNOWN** | **steps 2–6** | Not attempted while headless absent — honest, not faked |
| **END_TO_END_VERIFIED** | **NO** | Flags alone never equal E2E; health `ghidraConfigured` is **not** proof |

`CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN` — honored.

---

## Executed?

**No.** `analyzeHeadless` was not found. Live selftest: `executed=false`, `overall=FAILED`, `overallCode=MISSING_PREREQUISITE`.

**Exact blocker (frozen):**  
`MISSING_PREREQUISITE: GHIDRA_HOME unset, GHIDRA_HEADLESS unset, analyzeHeadless not on PATH, /opt/ghidra absent. Java present does not imply Ghidra.`

Evidence: `research/cycle11/agent_c/selftest.live.json`.

---

## Synthetic fixture (SHA-256)

| Field | Value |
|-------|-------|
| Primary path | `server/firmware-analysis/testdata/diagnostics/synthetic_cortex_m_thumb.bin` |
| Cycle-10 constant | `research/cycle10/fixtures/synthetic_cortex_m_thumb.bin` (`CYCLE10_FIXTURE`) |
| Size | 512 bytes |
| SHA-256 | `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea` |
| Marker | `SYNTH_C7_NOT_SCOOTER_FW` |

---

## Selftest checklist (8 steps)

| # | Step | Status | Notes |
|---|------|--------|-------|
| 1 | analyzeHeadless | **FAILED** | `MISSING_PREREQUISITE` |
| 2 | import | **UNKNOWN** | BinaryLoader not attempted |
| 3 | arch | **UNKNOWN** | Target `ARM:LE:32:Cortex` + `0x08000000` wired; not applied |
| 4 | analyze | **UNKNOWN** | Headless auto-analysis not started |
| 5 | functions_export | **UNKNOWN** | **no** fabricated `.functions.json` |
| 6 | cfg_export | **UNKNOWN** | **no** fabricated `.callgraph.json` |
| 7 | artifacts | **VERIFIED** | Honest absence — zero fabricated exports |
| 8 | sha256_metadata | **VERIFIED** | Fixture digest matches frozen Cycle-7/10 value |

**Overall:** `FAILED` / `MISSING_PREREQUISITE` — successful Ghidra execution **not** claimed.

---

## Implementation surface

| Path | Role |
|------|------|
| `server/firmware-analysis/diagnostics_ghidra.py` | Admin diagnostics selftest: fixed argv, lock, timeout, 8-step envelope |
| `server/firmware-analysis/testdata/diagnostics/` | Immutable synthetic bin copy + README |
| `server/firmware-analysis/test_diagnostics_ghidra.py` | Unit tests incl. mocked missing Ghidra + mock VERIFIED path |
| `research/cycle11/agent_c/selftest.live.json` | Frozen live probe on this VM |

### Policy (honored)

- **Fixed argv only** — `subprocess.run(..., shell=False)` with constant token list; no user shell, no arbitrary args
- **Timeouts** — default 180s headless; lock wait 30s
- **Concurrency** — in-process `threading.Lock` + cross-process O_EXCL lockfile
- **Missing Ghidra** — `FAILED`/`UNKNOWN` + `MISSING_PREREQUISITE`; never fake exports
- **No env dump / no secrets** — probe paths only

---

## Tests (this VM)

| Test | Result |
|------|--------|
| `test_diagnostics_ghidra` (7 cases) | **PASS** |
| Mocked missing Ghidra → FAILED/UNKNOWN + `MISSING_PREREQUISITE` | **PASS** |
| Mocked success pipeline → overall `VERIFIED` | **PASS** |
| Live selftest (`python3 diagnostics_ghidra.py`) | **exit 0**, `executed=false`, overall `FAILED`/`MISSING_PREREQUISITE` |

---

## Environment probe

| Check | Result |
|-------|--------|
| `GHIDRA_HOME` | **unset** |
| `GHIDRA_HEADLESS` | **unset** |
| `analyzeHeadless` on PATH | **absent** |
| `/opt/ghidra` | **absent** |
| Java | present — **impliesGhidra=false** |
| Fabricated exports | **none** |

---

## Hard bans (honored)

- No user shell / no arbitrary argv
- No fabricated Ghidra `.functions.json` / `.callgraph.json` / `.dec.c` when tools missing
- No claim of `VERIFIED` from `/health` `ghidraConfigured` alone
- No real encrypted ZT3 / Cycle-6 `FIRM.bin.enc` plaintext reconstruction
- No huge Ghidra download on this VM (document `MISSING_PREREQUISITE`)

---

## Bottom line

**GHIDRA executed?** No.  
**Grades:** CONFIGURED=no · AVAILABLE=no · VERIFIED=no · overall=**FAILED** (`MISSING_PREREQUISITE`) · steps 2–6=**UNKNOWN** · 7–8=**VERIFIED**.  
**Fixture SHA-256:** `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea`
