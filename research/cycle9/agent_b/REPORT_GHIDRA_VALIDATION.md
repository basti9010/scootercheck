# Cycle 9 Agent B — Ghidra Headless Validation

**Role:** GHIDRA VALIDATION  
**Date:** 2026-11-23 (UTC)  
**Base:** `cursor/prod-pipeline-forensic-c9-b100` @ `49dff04`  
**Branch:** `cursor/ghidra-validation-c9-b100`  
**Subject:** synthetic Cortex-M Thumb only (`SYNTH_C7_NOT_SCOOTER_FW`) — **no** real encrypted ZT3 plaintext reconstruction

---

## Epistemic grades

| Grade | Verdict | Rationale |
|-------|---------|-----------|
| **IMPLEMENTED** | **YES** | `ghidra_decompile.py`, `ghidra_scripts/*.java`, Cycle-8/9 SKIP-safe runners present; Cycle-9 harness adds env probe + Cycle-9 proof vocabulary |
| **TESTED** | **PARTIAL** | SKIP path + preflight + env probe + unit skip marker + offline export fixtures exercised; headless import **not** run |
| **DEPLOYED** | **NO** | Cloud Agent VM has no `GHIDRA_HOME` / `analyzeHeadless`; `/opt/ghidra` directory missing |
| **END_TO_END_VERIFIED** | **NO** | Full import → analyze → function detection → callgraph JSON path blocked by missing Ghidra install — **not claimed** |

---

## Environment probe (exact cause)

| Check | Result |
|-------|--------|
| `GHIDRA_HOME` | **unset** |
| `GHIDRA_HEADLESS` | **unset** |
| `analyzeHeadless` on PATH | **absent** |
| `/opt/ghidra` | **dir_missing** (no `ghidra_*/support/analyzeHeadless`) |
| `ghidra_configured()` (`ghidra_decompile.py`) | **False** (matches probe) |
| Java | OpenJDK 21 at `/usr/bin/java` — **does not** imply Ghidra |

**Exact missing cause (frozen):**  
`MISSING_PREREQUISITE: GHIDRA_HOME unset, GHIDRA_HEADLESS unset, analyzeHeadless not on PATH, /opt/ghidra absent. Java present does not imply Ghidra.`

Evidence: `research/cycle9/agent_b/env_probe.skip_run.json`, `research/cycle9/agent_b/prereqs.skip_run.json`.

---

## Proof points

Frozen SKIP-run evidence: `research/cycle9/agent_b/proof_points.skip_run.json`.

| # | Proof point | Status | Notes |
|---|-------------|--------|-------|
| 1 | Import | **SKIP** | No `analyzeHeadless`; BinaryLoader import not attempted |
| 2 | Architecture | **SKIP** | Target `ARM:LE:32:Cortex` + base `0x08000000` wired; Ghidra language assignment not executed. Fixture IVT preflight **PASS** (SP `0x20020000`, Reset Thumb `0x08000100`) |
| 3 | Static analysis | **SKIP** | Headless auto-analysis not started |
| 4 | Function detection | **SKIP** | `SeedCortexMEntryPoints.java` + `ExportFunctionAnalysis.java` present; **no** fabricated `.functions.json` |
| 5 | Control-flow | **SKIP** | `ExportCallGraph.java` present; **no** fabricated `.callgraph.json` |
| 6 | JSON export | **PASS** | Validation proof envelope written; **not** a Ghidra export. No fabricated function/callgraph JSON under `out_synthetic/` |
| 7 | Error handling | **PASS** | Runner prints `SKIP` + `MISSING_PREREQUISITE`; exit **0**; JSON records exact cause |

**Overall:** `SKIPPED_NO_GHIDRA` — successful Ghidra run **not** claimed.

---

## Integration surface (validated as present, not E2E)

### Python driver — `server/firmware-analysis/ghidra_decompile.py`

- Resolves headless: `GHIDRA_HEADLESS` → `GHIDRA_HOME/support/analyzeHeadless` → nested `ghidra_*` → PATH → `/opt/ghidra/ghidra_*`
- Import: `BinaryLoader`, `-processor ARM:LE:32:Cortex`, `-loader-baseAddr 0x08000000`
- Pre: `SeedCortexMEntryPoints.java`
- Post: `ExportAllDecompiled`, `ExportFunctionAnalysis`, `ExportCallGraph`, …
- Returns `(False, "Ghidra not configured…")` when tools missing — **no silent fake success**

### Scripts — `server/firmware-analysis/ghidra_scripts/`

| Script | Role for proof points |
|--------|------------------------|
| `SeedCortexMEntryPoints.java` | IVT → Thumb functions (feeds #3/#4) |
| `ExportFunctionAnalysis.java` | Structured function inventory (#4, #6) |
| `ExportCallGraph.java` | Control-flow edges (#5, #6) |
| `ExportAllDecompiled.java` | Decompiled C dump |

### Offline tests (this VM)

| Test | Result |
|------|--------|
| `test_ghidra_integration.GhidraIntegrationSkippedMarkerTests` | **PASS** (`ghidra_configured() is False`) |
| `test_ghidra_export_fixtures` | **PASS** (fixture JSON + FunctionDiff; no headless) |
| Cycle-8 `./research/cycle8/fixtures/run_ghidra_headless_synthetic.sh` | **exit 0**, overall `SKIPPED_NO_GHIDRA` |
| Cycle-9 `./research/cycle9/fixtures/run_ghidra_headless_synthetic.sh` | **exit 0**, overall `SKIPPED_NO_GHIDRA` |

---

## Fixtures

| Path | Purpose |
|------|---------|
| `research/cycle9/fixtures/synthetic_cortex_m_thumb.bin` | 512 B Cortex-M Thumb IVT stub (SHA-256 `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea`) |
| `research/cycle9/fixtures/validate_ghidra_prereqs.py` | Preflight + per-path env probe + driver cross-check |
| `research/cycle9/fixtures/run_ghidra_headless_synthetic.sh` | SKIP-safe runner; Cycle-9 proof names; refuses fabricated exports on SKIP |
| `research/cycle9/fixtures/README.md` | Operator notes |
| `research/cycle8/fixtures/*` | Upstream Cycle-8 assets (still valid) |
| `server/firmware-analysis/ghidra_scripts/` | Headless export scripts |

### Re-run on a host with Ghidra

```bash
GHIDRA_HOME=/opt/ghidra/ghidra_*_PUBLIC \
  ./research/cycle9/fixtures/run_ghidra_headless_synthetic.sh
# Expect: overallStatus PASS, non-empty synthetic.functions.json + synthetic.callgraph.json
# Fail only when GHIDRA_HOME is set but headless errors/timeouts
```

---

## Hard bans (honored)

- No reconstruction of real encrypted ZT3 / Cycle-6 `FIRM.bin.enc` plaintext
- No fabricated Ghidra `.functions.json` / `.callgraph.json` / `.dec.c` when tools are missing
- No claim of a successful Ghidra run without `analyzeHeadless`

---

## Bottom line

**GHIDRA available?** No.

Pipeline code and synthetic fixture are **IMPLEMENTED**; SKIP-safe validation is **TESTED** on this VM; production Ghidra import/export is **not DEPLOYED** here and **not END_TO_END_VERIFIED**. Proof points **1–5 = SKIP**, **6–7 = PASS** under documented missing prerequisite.
