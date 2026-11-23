# Cycle 8 Agent B — Ghidra Headless Validation

**Role:** GHIDRA ENGINEER  
**Date:** 2026-11-23 (UTC)  
**Base:** `cursor/server-deploy-ghidra-ios-c8-b100`  
**Branch:** `cursor/ghidra-engine-validation-979c`  
**Subject:** synthetic Cortex-M Thumb only (`SYNTH_C7_NOT_SCOOTER_FW`) — **no** real encrypted ZT3 plaintext reconstruction

---

## Epistemic grades

| Grade | Verdict | Rationale |
|-------|---------|-----------|
| **IMPLEMENTED** | **YES** | `ghidra_decompile.py`, `ghidra_scripts/*.java`, Cycle-7/8 SKIP-safe runners present and consistent |
| **TESTED** | **PARTIAL** | SKIP path + preflight + unit skip marker + offline export fixtures exercised; headless import **not** run |
| **DEPLOYED** | **NO** | Cloud Agent VM has no `GHIDRA_HOME` / `analyzeHeadless`; Hetzner host not reachable from this environment |
| **END_TO_END_VERIFIED** | **NO** | Full import → analyze → `.functions.json` / `.callgraph.json` path blocked by missing Ghidra install |

---

## Environment probe

| Check | Result |
|-------|--------|
| `GHIDRA_HOME` | **unset** |
| `GHIDRA_HEADLESS` | **unset** |
| `analyzeHeadless` on PATH | **absent** |
| `/opt/ghidra/ghidra_*/support/analyzeHeadless` | **absent** |
| `ghidra_configured()` (`ghidra_decompile.py`) | **False** |
| Java | OpenJDK 21 present (**does not** imply Ghidra) |

**Missing prerequisite (documented, not faked):** install Ghidra PUBLIC and set `GHIDRA_HOME` (or `GHIDRA_HEADLESS`) to a tree containing `support/analyzeHeadless`.

---

## Proof points

Frozen SKIP-run evidence: `research/cycle8/agent_b/proof_points.skip_run.json`, `research/cycle8/agent_b/prereqs.skip_run.json`.

| # | Proof point | Status | Notes |
|---|-------------|--------|-------|
| 1 | Firmware imported | **SKIP** | No `analyzeHeadless`; BinaryLoader import not attempted |
| 2 | Architecture assigned correctly (ARM Cortex-M LE) | **SKIP** | Target `ARM:LE:32:Cortex` + base `0x08000000` wired in code/runner; Ghidra language assignment not executed. Fixture IVT preflight **PASS** (SP `0x20020000`, Reset Thumb `0x08000100`) |
| 3 | Static analysis started | **SKIP** | Headless auto-analysis not started |
| 4 | Function info exported | **SKIP** | `ExportFunctionAnalysis.java` present; **no** fabricated `.functions.json` |
| 5 | Control-flow info exported | **SKIP** | `ExportCallGraph.java` present; **no** fabricated `.callgraph.json` |
| 6 | Results stored structured | **PASS** | Validation proof envelope + prereq JSON written; schema for real exports remains `ExportFunctionAnalysis` / `ExportCallGraph` (see Cycle-7 design). Not a substitute for Ghidra export E2E |
| 7 | Errors documented when tools missing | **PASS** | Runner prints `SKIP` + `MISSING_PREREQUISITE`; exit **0**; JSON records the gap |

---

## Integration surface (validated as present, not E2E)

### Python driver — `server/firmware-analysis/ghidra_decompile.py`

- Resolves headless: `GHIDRA_HEADLESS` → `GHIDRA_HOME/support/analyzeHeadless` → nested `ghidra_*` → PATH → `/opt/ghidra/ghidra_*`
- Import: `BinaryLoader`, `-processor ARM:LE:32:Cortex`, `-loader-baseAddr 0x08000000`
- Pre: `SeedCortexMEntryPoints.java`
- Post: `ExportAllDecompiled`, `ExportSpeedXrefs`, `ExportLimitFunctions`, `ExportFunctionAnalysis`, `ExportCallGraph`, optional `ExportDataFlowSummary`
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
| Cycle-8 `./run_ghidra_headless_synthetic.sh` | **exit 0**, overall `SKIPPED_NO_GHIDRA` |

---

## Fixtures (Cycle 8)

| Path | Purpose |
|------|---------|
| `research/cycle8/fixtures/synthetic_cortex_m_thumb.bin` | 512 B Cortex-M Thumb IVT stub (SHA-256 `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea`, identical to Cycle 7) |
| `research/cycle8/fixtures/validate_ghidra_prereqs.py` | Preflight: blob/IVT + script presence + headless resolution |
| `research/cycle8/fixtures/run_ghidra_headless_synthetic.sh` | Isolated SKIP-safe runner; writes `proof_points.json`; full export when Ghidra present |
| `research/cycle8/fixtures/README.md` | Operator notes |
| `research/cycle7/fixtures/*` | Upstream Cycle-7 assets (unchanged contract) |

### Re-run on a host with Ghidra

```bash
GHIDRA_HOME=/opt/ghidra/ghidra_*_PUBLIC \
  ./research/cycle8/fixtures/run_ghidra_headless_synthetic.sh
# Expect: overallStatus PASS, non-empty synthetic.functions.json + synthetic.callgraph.json
# Fail only when GHIDRA_HOME is set but headless errors/timeouts
```

---

## Hard bans (honored)

- No reconstruction of real encrypted ZT3 / Cycle-6 `FIRM.bin.enc` plaintext
- No fabricated Ghidra `.functions.json` / `.callgraph.json` / `.dec.c` when tools are missing
- No activation / tuning sequence reconstruction

---

## Bottom line

**GHIDRA_HOME present?** No.  

Pipeline code and synthetic fixture are **IMPLEMENTED**; SKIP-safe validation is **TESTED** on this VM; production Ghidra import/export is **not DEPLOYED** here and **not END_TO_END_VERIFIED**. Proof points **1–5 = SKIP**, **6–7 = PASS** under documented missing prerequisite.
