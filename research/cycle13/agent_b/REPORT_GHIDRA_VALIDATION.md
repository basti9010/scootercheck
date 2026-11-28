# Cycle 13 Agent B — Ghidra Specialist Report

**Role:** GHIDRA SPECIALIST  
**Date:** 2026-11-28 (UTC)  
**Repo branch (work):** `cursor/cycle13-ghidra-agent-b-650a`  
**Base:** `cursor/cycle13-prod-ghidra-b100`  
**Live API:** `https://api.tuningscanner.de/scootercheck-fw`  
**Deployed SHA (given):** `20c5d0ce423bd5a953dccdff02cda03a954d8f18`  
**Subject:** synthetic Cortex-M Thumb only (`SYNTH_C7_NOT_SCOOTER_FW`) — **no** real scooter firmware

---

## Epistemic status (this agent run)

| Claim | Grade | Evidence |
|-------|-------|----------|
| Live `/health` `ghidraConfigured:true` + `ghidraEnabled:true` | **CONFIRMED** | Public health JSON 2026-11-28 |
| That health pair equals Ghidra **VERIFIED** | **CONFIRMED false** | Code + docs: flags ≤ CONFIGURED/AVAILABLE |
| Diagnostics routes wired at deployed SHA | **CONFIRMED** | `app.py` includes `create_diagnostics_router` @ `20c5d0c` |
| Live `POST /v1/diagnostics/selftest` reachable unauthenticated | **CONFIRMED false** | HTTP **401** `missing or invalid credentials` |
| This Cloud Agent can mint admin JWT / hold `ADMIN_API_TOKEN` | **CONFIRMED false** | Env empty; live `adminApiTokenConfigured:false` |
| This Cloud Agent can SSH Hetzner / run host headless | **CONFIRMED false** | Policy: NO SSH; no secrets |
| Local `analyzeHeadless` on agent VM | **CONFIRMED absent** | `MISSING_PREREQUISITE` selftest |
| Fixture SHA-256 integrity | **CONFIRMED** | Matches frozen digest |
| Live Ghidra headless **VERIFIED** (import→export) | **INCOMPLETE** | No admin auth + no SSH → **not executed** |

**Bottom line:** Live is **CONFIGURED** (health). Agent B did **not** obtain **VERIFIED**. Do not claim live Ghidra VERIFIED from this run.

---

## 1. Code surface reviewed

| Path | Role |
|------|------|
| `server/firmware-analysis/diagnostics_ghidra.py` | 8-step admin selftest; fixed argv; grades envelope |
| `server/firmware-analysis/ghidra_decompile.py` | Production headless runner (`ghidra_configured()` used by `/health`) |
| `server/firmware-analysis/diagnostics_routes.py` | `POST /v1/diagnostics/selftest` → `run_ghidra_diagnostics_selftest()` |
| `server/firmware-analysis/diagnostics_status.py` | Status probe: resolvable headless ⇒ **AVAILABLE** (explicitly not VERIFIED) |
| `server/firmware-analysis/diagnostics_models.py` | Grade ladder + `SelftestRequest` |
| `server/firmware-analysis/testdata/diagnostics/synthetic_cortex_m_thumb.bin` | Immutable 512 B fixture |
| `server/firmware-analysis/testdata/thumb_validation/` | Phase 2.2A Thumb GT (separate from diagnostics fixture) |
| `research/cycle10/fixtures/run_ghidra_headless_synthetic.sh` | Host/CLI proof script (same fixture digest) |
| `server/firmware-analysis/deploy/post-deploy-smoke.sh` | Health + optional GET diagnostics status only |
| `server/firmware-analysis/staging_harness.py` | Local TestClient env with admin token (unit tests) |

Deployed SHA **includes** diagnostics modules + router wiring (ancestor of current HEAD).

---

## 2. Exact selftest → analyzeHeadless steps

Entry: `run_ghidra_diagnostics_selftest()` in `diagnostics_ghidra.py`  
(also CLI: `python3 diagnostics_ghidra.py`; also API when `includeGhidra:true`).

### Constants (fixed — no user argv)

| Item | Value |
|------|-------|
| Fixture | `testdata/diagnostics/synthetic_cortex_m_thumb.bin` (fallback Cycle-10 path) |
| SHA-256 | `3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea` |
| Marker | `SYNTH_C7_NOT_SCOOTER_FW` |
| Processor | `ARM:LE:32:Cortex` |
| Loader | `BinaryLoader` |
| Base | `0x08000000` |
| Project name | `Cycle11DiagGhidra` |
| Timeout | 180 s |
| Shell | **never** (`subprocess.run(..., shell=False)`) |

### Headless resolution order (`_resolve_headless`)

1. `GHIDRA_HEADLESS` if path exists  
2. `$GHIDRA_HOME/support/analyzeHeadless`  
3. `$GHIDRA_HOME/ghidra_*/support/analyzeHeadless`  
4. `PATH:analyzeHeadless`  
5. `/opt/ghidra/ghidra_*/support/analyzeHeadless`

Same resolution family as `ghidra_decompile._headless_bin()` (health `ghidraConfigured`).

### Fixed argv (`_build_fixed_headless_argv`)

```text
analyzeHeadless
  <temp>/proj
  Cycle11DiagGhidra
  -import <fixture.bin>
  -processor ARM:LE:32:Cortex
  -cspec default
  -loader BinaryLoader
  -loader-baseAddr 0x08000000
  -scriptPath <repo>/ghidra_scripts
  -preScript SeedCortexMEntryPoints.java          # if present
  -postScript ExportAllDecompiled.java     <temp>/out/diag.dec.c
  -postScript ExportFunctionAnalysis.java  <temp>/out/diag.functions.json
  -postScript ExportCallGraph.java         <temp>/out/diag.callgraph.json
  -deleteProject
```

Env for the child: `GHIDRA_BASE_ADDR=0x08000000`, `SCOOTERCHECK_LOADER_BASE=0x08000000`.

### 8-step checklist (what VERIFIED requires)

| # | Step | Pass criterion |
|---|------|----------------|
| 1 | analyzeHeadless | Binary resolved + readable/executable |
| 2 | import | Headless exit 0 (BinaryLoader) |
| 3 | arch | Exit 0 with requested `ARM:LE:32:Cortex` + base |
| 4 | analyze | Exit 0 (auto-analysis completed) |
| 5 | functions_export | `diag.functions.json` present, size>0, JSON object parseable |
| 6 | cfg_export | `diag.callgraph.json` present, size>0, JSON object parseable (**CFG proxy**; not `ExportDataFlowSummary`) |
| 7 | artifacts | Import OK **and** steps 5–6 OK; digests recorded; **never** fabricate |
| 8 | sha256_metadata | Fixture digest == frozen SHA-256 |

**Overall `grades.verified=true` / `endToEndVerified=true` only if all 8 steps are `VERIFIED` and headless actually ran (`executed=true`).**

Note: decompile `diag.dec.c` is produced but **not** required for overall VERIFIED. Dataflow (`ExportDataFlowSummary.java` / `*.dataflow.json`) is used by production `ghidra_decompile.py`, **not** by diagnostics selftest.

### Missing-tool honesty

If headless unresolved: steps 1=`FAILED`/`MISSING_PREREQUISITE`, 2–6=`UNKNOWN`, 7–8 can still `VERIFIED` (honest absence + fixture hash). `executed=false`. No fake exports.

---

## 3. Can this environment trigger live selftest?

**Answer: NO.**

| Path | Result |
|------|--------|
| `POST …/v1/diagnostics/selftest` no auth | **401** |
| Fake Bearer / fake `X-ScooterCheck-Token` | **401** |
| `ADMIN_API_TOKEN` in agent env | **unset** |
| Live `adminApiTokenConfigured` | **false** (health) |
| Live JWT | `jwtConfigured:true` but agent has **no** `JWT_SECRET` and **no** admin JWT |
| Shared `API_TOKEN` | Explicitly **denied** by diagnostics gate (even if known) |
| SSH to Hetzner | **Forbidden** for this agent |
| Local Ghidra | **Absent** → CLI selftest = `MISSING_PREREQUISITE` only |

Live auth posture (health, CONFIRMED):

- `authMode=separated`, `authSecurityOk=true`, `apiTokenGrantsAdmin=false`
- Advisory: `ADMIN_API_TOKEN unset — admin endpoints require JWT role=admin only`

So the **only** live API path today is a **JWT with `role=admin`**. Agent B cannot mint or obtain one without secrets.

Routes **are** wired (401 ≠ 404). Endpoint exists; auth blocks this agent.

---

## 4. Reproducible synthetic selftest procedure for PM

Prefer **existing** code. Three equivalent proof paths (synthetic only).

### Path A — Host CLI (preferred once SSH/Freigabe; no API token needed)

On the Hetzner app host (service env already has Ghidra if `ghidraConfigured=true`):

```bash
cd /path/to/server/firmware-analysis   # deployed app dir
# Ensure GHIDRA_HOME or GHIDRA_HEADLESS matches the service unit env
./.venv/bin/python diagnostics_ghidra.py | tee /tmp/ghidra-selftest-c13.json
```

**Pass (VERIFIED):** JSON with

- `executed: true`
- `grades.verified: true`
- `grades.endToEndVerified: true`
- `overallCode: "OK"`
- all 8 `steps[].status == "VERIFIED"`
- `fixture.matches: true`
- `run.exports.functions` / `callgraph` with `present:true`, `size>0`, `sha256` set

**Fail honestly:** `MISSING_PREREQUISITE`, `TIMEOUT`, `EXPORT_MISSING`, `FAILED` — keep the JSON; do not invent exports.

### Path B — Live API (needs admin auth)

Ops must either:

1. Set `ADMIN_API_TOKEN` on the service and restart, **or**
2. Issue a short-lived JWT (`role=admin`) with production `JWT_SECRET` (ops-only).

Then:

```bash
BASE=https://api.tuningscanner.de/scootercheck-fw
# Prefer dedicated admin token header once configured:
#   -H "X-ScooterCheck-Token: $ADMIN_API_TOKEN"
# Or admin JWT:
#   -H "Authorization: Bearer $ADMIN_JWT"

curl -sS -X POST "$BASE/v1/diagnostics/selftest" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -d '{"includeTea":false,"includeGhidra":true,"includeWorkers":false}'

# Poll:
curl -sS "$BASE/v1/diagnostics/selftest/<jobId>" \
  -H "Authorization: Bearer $ADMIN_JWT"
```

Inspect `result.steps[]` entry `id=ghidra`: require `grade=VERIFIED` and `executionVerified=true`.  
Optionally also `GET /v1/diagnostics/status` — ghidra component grade remains ≤ AVAILABLE until selftest proves VERIFIED.

### Path C — Repo shell proof (same fixture; offline host with Ghidra)

```bash
cd research/cycle10/fixtures
export GHIDRA_HOME=/opt/ghidra/ghidra_*_PUBLIC   # as installed
export GHIDRA_SCRIPT_DIR=../../../server/firmware-analysis/ghidra_scripts
./run_ghidra_headless_synthetic.sh
```

Expect `overallStatus=PASS`, non-empty `synthetic.functions.json` + `synthetic.callgraph.json`, `sha256Binding.matches=true`.

### Path D — Local staging (unit / no live Ghidra)

`staging_harness` + `test_diagnostics_routes.py` prove **auth wiring** with synthetic admin tokens. They do **not** prove production headless VERIFIED (`enable_ghidra=False` in that test).

### Smoke note

`deploy/post-deploy-smoke.sh` with `SMOKE_ADMIN_TOKEN` only hits **GET** `/v1/diagnostics/status` and explicitly grades `END_TO_END_VERIFIED=NO`. Smoke alone never VERIFIES Ghidra.

---

## 5. Artifacts: CONFIGURED vs VERIFIED

### Merely CONFIGURED / AVAILABLE (not proof)

| Artifact | Meaning |
|----------|---------|
| `/health` `ghidraConfigured:true` | `ghidra_configured()` found `analyzeHeadless` path |
| `/health` `ghidraEnabled:true` | `ENABLE_GHIDRA` not disabled |
| Diagnostics status component grade `AVAILABLE` | Same existence probe; detail says “not VERIFIED” |
| Env `GHIDRA_HOME` / `GHIDRA_HEADLESS` set | At most CONFIGURED if binary missing |
| Java installed | Explicitly **does not** imply Ghidra |

### Required for VERIFIED

| Artifact | Required |
|----------|----------|
| Selftest envelope `executed:true` | Yes |
| `grades.verified` / `endToEndVerified:true` | Yes |
| Step 1–8 all `VERIFIED` | Yes |
| `run.exports.functions` present + size>0 + `jsonOk` + **sha256** | Yes |
| `run.exports.callgraph` present + size>0 + `jsonOk` + **sha256** | Yes (CFG evidence) |
| Fixture `sha256` match + marker | Yes |
| Fixed `argvFixed` recorded (audit) | Yes (in `run`) |
| Headless log tail (`logTail` / host log) | Strongly recommended for audit |
| `diag.dec.c` | Optional (produced, not gate) |
| `*.dataflow.json` | **Not** in diagnostics gate today |

Temp export files are deleted with the TemporaryDirectory; **digests in the JSON envelope** are the durable proof for Path A/B. Path C persists files under `out_synthetic/`.

---

## 6. Local agent execution evidence (this VM)

```text
python3 diagnostics_ghidra.py
→ executed=false
→ overallCode=MISSING_PREREQUISITE
→ grades.verified=false, endToEndVerified=false
→ fixture.actual=3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea (match)
→ steps: 1 FAILED; 2–6 UNKNOWN; 7–8 VERIFIED
```

Unit tests: `pytest test_diagnostics_ghidra.py` → **7 passed** (mocked missing + mocked success; no live headless).

---

## 7. Minimal patch proposals (file-level)

No mock-success paths. These do **not** invent VERIFIED.

| Priority | File | Proposal | Why |
|----------|------|----------|-----|
| P1 ops | Host systemd/env | Set `ADMIN_API_TOKEN`; keep `API_TOKEN_GRANTS_ADMIN=0` | Live cannot use dedicated admin header today (`adminApiTokenConfigured:false`); JWT-only is fragile for smoke |
| P2 | `diagnostics_ghidra.py` | Add `ExportAllDecompiled.java` to `REQUIRED_SCRIPTS` | Already in fixed argv; missing script → obscure headless fail instead of early FAIL |
| P3 | `deploy/post-deploy-smoke.sh` | Optional gated `POST /v1/diagnostics/selftest` when `SMOKE_ADMIN_TOKEN` + `SMOKE_GHIDRA_SELFTEST=1`; require `executionVerified` | Today smoke stops at status GET; never VERIFIES |
| P4 | `diagnostics_ghidra.py` | Optional step/export for `ExportDataFlowSummary.java` → `diag.dataflow.json` when script present | Aligns “CFG/dataflow” wording with Phase 2.3.x; **do not** gate VERIFIED on it until fixtures prove stable on the 512 B synth blob |
| P5 cosmetic | `diagnostics_ghidra.py` envelope | Bump `cycle`/`agent` labels to 13/B | Metadata only |

**Non-proposals:** Do not stub exports when headless missing; do not treat health flags as VERIFIED; do not add shell=True or caller argv.

**Code gaps blocking live VERIFIED from this agent?** None in the headless pipeline itself when Ghidra + fixture + scripts are on the host. Blockers are **auth + host access**, not missing analyzeHeadless wiring. Deployed tree already ships scripts + `testdata/diagnostics/synthetic_cortex_m_thumb.bin` via `deploy-manifest.txt`.

---

## 8. Structured verdict

```text
STATUS: INCOMPLETE for live VERIFIED
CONFIGURED (live health): CONFIRMED
AVAILABLE (live path resolves): HYPOTHESIS — health true implies resolvable on host; Agent B did not run headless there
VERIFIED (live import/analyze/export): INCOMPLETE — no admin credential, no SSH, no local Ghidra
SELFTEST CODE PATH: CONFIRMED present + wired @ 20c5d0c
FIXTURE SHA-256: CONFIRMED
HONEST MISSING PATH (this VM): CONFIRMED FAILED/MISSING_PREREQUISITE
```

### Blockers (frozen)

1. No `ADMIN_API_TOKEN` / admin JWT in this environment  
2. Live `adminApiTokenConfigured=false` (JWT admin only)  
3. NO SSH to Hetzner  
4. No `analyzeHeadless` on the Cloud Agent VM  

### Reproduction for PM (shortest)

1. On Hetzner with service env: `python3 diagnostics_ghidra.py`  
2. Or with admin JWT/token: `POST /v1/diagnostics/selftest` `{"includeGhidra":true}` and poll until `executionVerified=true`  
3. Archive the JSON; require fixture SHA + functions/callgraph export digests  

**Do not claim live Ghidra VERIFIED without that execution evidence.**
