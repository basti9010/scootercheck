# Cycle 10 Agent B — Ghidra Headless Execution

**Role:** GHIDRA EXECUTION  
**Date:** 2026-11-23 (UTC)  
**Base:** `cursor/hetzner-ghidra-live-c10-b100` @ `3d513db`  
**Branch:** `cursor/ghidra-execution-c10-b100`  
**Subject:** synthetic Cortex-M Thumb only (`SYNTH_C7_NOT_SCOOTER_FW`) — **no** real encrypted ZT3 plaintext

---

## Epistemic grades

| Grade | Verdict | Rationale |
|-------|---------|-----------|
| **IMPLEMENTED** | **YES** | Cycle-10 SKIP-safe harness under `research/cycle10/fixtures/` with nine-point proof checklist, SHA-256 binding, persist manifest, Freigabe doc; upstream `ghidra_decompile.py` + `ghidra_scripts/*.java` present |
| **TESTED** | **PARTIAL** | SKIP path + preflight + install probe + SHA-256 bind + persist exercised (exit 0). Headless import/analyze/export **not** run — tools absent |
| **DEPLOYED** | **NO** | This Cloud Agent VM has no `GHIDRA_HOME` / `analyzeHeadless`; `/opt/ghidra` missing. No huge Ghidra download (policy: document `MISSING_PREREQUISITE`) |
| **END_TO_END_VERIFIED** | **NO** | Full Install→Import→Analyze→Functions→CFG→JSON path blocked. **Not claimed.** `ghidraConfigured=true` on public `/health` is **not** execution proof |

---

## Executed?

**No.** `analyzeHeadless` was not found. Overall: `SKIPPED_NO_GHIDRA`.

**Exact blocker (frozen):**  
`MISSING_PREREQUISITE: GHIDRA_HOME unset, GHIDRA_HEADLESS unset, analyzeHeadless not on PATH, /opt/ghidra absent. Java present does not imply Ghidra.`

---

## Synthetic fixture (SHA-256)

| Field | Value |
|-------|-------|
| Path | `research/cycle10/fixtures/synthetic_cortex_m_thumb.bin` |
| Size | 512 bytes |
| SHA-256 | `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea` |
| IVT | SP `0x20020000`, Reset Thumb `0x08000100` @ flash base `0x08000000` |
| Marker | `SYNTH_C7_NOT_SCOOTER_FW` |

---

## Proof checklist

Frozen SKIP-run evidence: `research/cycle10/agent_b/proof_points.skip_run.json`.

| # | Proof point | Status | Notes |
|---|-------------|--------|-------|
| 1 | Install | **SKIP** | `analyzeHeadless` unresolved; OpenJDK 21 present but does **not** imply Ghidra |
| 2 | Import | **SKIP** | BinaryLoader import not attempted |
| 3 | Architecture | **SKIP** | Target `ARM:LE:32:Cortex` + base `0x08000000` documented; language assignment not executed |
| 4 | Static analysis | **SKIP** | Headless auto-analysis not started |
| 5 | Functions | **SKIP** | Scripts present; **no** fabricated `.functions.json` |
| 6 | CFG | **SKIP** | `ExportCallGraph.java` present; **no** fabricated `.callgraph.json` |
| 7 | JSON export | **PASS** | Proof envelope only — **not** a Ghidra export |
| 8 | Persist results | **PASS** | `proof_points.json` + `sha256_binding.json` + `persist_manifest.json` under `out_synthetic/` |
| 9 | SHA-256 binding | **PASS** | Fixture digest matches frozen Cycle-7/8/9 value |

**Overall:** `SKIPPED_NO_GHIDRA` — successful Ghidra execution **not** claimed.

---

## Environment probe

| Check | Result |
|-------|--------|
| `GHIDRA_HOME` | **unset** |
| `GHIDRA_HEADLESS` | **unset** |
| `analyzeHeadless` on PATH | **absent** |
| `/opt/ghidra` | **dir_missing** |
| `ghidra_configured()` | **False** (matches probe) |
| Java | OpenJDK 21 — **impliesGhidra=false** |
| Fabricated exports under `out_synthetic/` | **none** |

Evidence: `env_probe.skip_run.json`, `prereqs.skip_run.json`, `sha256_binding.skip_run.json`, `persist_manifest.skip_run.json`.

---

## Artifacts (this run)

| Path | Role |
|------|------|
| `research/cycle10/fixtures/` | SKIP-safe harness + synthetic bin + Freigabe doc |
| `research/cycle10/fixtures/FREIGABE_GHIDRA_HOST.md` | What host/CI need for a real PASS |
| `research/cycle10/agent_b/proof_points.skip_run.json` | Frozen nine-point checklist |
| `research/cycle10/agent_b/sha256_binding.skip_run.json` | Frozen digest binding |
| `research/cycle10/agent_b/persist_manifest.skip_run.json` | Frozen persist list |
| `research/cycle10/agent_b/env_probe.skip_run.json` | Frozen env probe |
| `research/cycle10/agent_b/prereqs.skip_run.json` | Frozen preflight |

**Ghidra export artifacts (`.functions.json` / `.callgraph.json` / `.dec.c`):** **absent by design** — not fabricated.

### Re-run when Freigabe provides Ghidra

```bash
GHIDRA_HOME=/opt/ghidra/ghidra_*_PUBLIC \
  ./research/cycle10/fixtures/run_ghidra_headless_synthetic.sh
# Expect: overallStatus PASS + non-empty synthetic.functions.json + synthetic.callgraph.json
```

See `research/cycle10/fixtures/FREIGABE_GHIDRA_HOST.md`.

---

## Hard bans (honored)

- No reconstruction of real encrypted ZT3 / Cycle-6 `FIRM.bin.enc` plaintext
- No fabricated Ghidra `.functions.json` / `.callgraph.json` / `.dec.c`
- No claim of successful Ghidra run without `analyzeHeadless`
- No claim of success from `ghidraConfigured=true` alone
- No huge Ghidra download on this VM (document `MISSING_PREREQUISITE`)

---

## Bottom line

**GHIDRA executed?** No.  
**Blocker:** `MISSING_PREREQUISITE` — no install / `GHIDRA_HOME` / `analyzeHeadless` on this Cloud Agent VM.  
**Harness:** Cycle-10 nine-point SKIP-safe runner ready; SHA-256 of synthetic bin bound and persisted.
