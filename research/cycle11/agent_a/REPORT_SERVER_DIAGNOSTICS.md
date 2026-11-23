# Cycle 11 AGENT A – Server Diagnostics

**Date:** 2026-11-23 (Europe/Berlin)  
**Branch:** `cursor/server-diagnostics-agent-a-b100`  
**Base:** `cursor/server-diagnostics-c11-b100` @ `9c6b153`  
**Scope:** Inventory FastAPI `server/firmware-analysis/`; propose + implement diagnostics modules as **new files only** (no `app.py` wire).  
**Hard bans:** no secrets, no env dump, no shell API, no prod deploy.

Evidence: **REPO** (code inventory + new modules). No Hetzner host access claimed.

---

## Verdict

Diagnostics API shape is **IMPLEMENTED** as draft modules. Routes are **NOT wired** into `APP` (`# wire in PM`).  
Auth gate is **stricter than `require_admin`**: refuses `auth=open` and `shared_token_admin` (API_TOKEN_GRANTS_ADMIN=1); accepts **JWT `role=admin` or `ADMIN_API_TOKEN` only**.

TEA/Ghidra grades stop at **AVAILABLE** from existence probes — **VERIFIED** deferred to Agents B/C.

---

## 1. Inventory (REPO)

### Health

| Item | Location |
|------|----------|
| `GET /health` | `app.py` — open; flags only (decrypt/ghidra/jwt/api/admin tokens configured, authMode, authSecurityOk/Critical/Warnings, tool `*Configured`, retention) |
| Auth helpers | `_auth_mode`, `_auth_security_warnings`, `_auth_security_ok` |

### TEA / DECRYPT_CMD

| Item | Location |
|------|----------|
| Env | `DECRYPT_CMD` |
| Runner | `run_decrypt()` — subprocess wrapper, 120s timeout |
| Example | `decrypt-firm.example.sh` → `/opt/scootercheck/decrypt-firm.sh` on host |
| Health flag | `decryptConfigured: bool(DECRYPT_CMD)` — **not** execution proof |

### Ghidra

| Item | Location |
|------|----------|
| Config | `ghidra_configured()` / `GHIDRA_HOME` / `GHIDRA_HEADLESS` / `ENABLE_GHIDRA` |
| Run | `ghidra_decompile.run_ghidra_decompile` + `ghidra_scripts/*.java` |
| Lock | `_HEAVY_ANALYSIS_LOCK` (single-flight with angr) |
| Health | `ghidraConfigured`, `ghidraEnabled` — **not** VERIFIED |

### Workers / jobs

| Item | Detail |
|------|--------|
| Model | In-process FastAPI `BackgroundTasks` → `process_job` (no separate queue daemon) |
| Store | `WORK_DIR` / `PLAINTEXT_STORE` / `DECOMPILE_STORE`; `status.json` per job |
| Caps | `JOB_RETENTION_DAYS`, `MAX_STORED_JOBS` |
| Systemd | `deploy/scootercheck-fw.service` — uvicorn `127.0.0.1:8088` |

### Auth

| Mechanism | Admin? |
|-----------|--------|
| Bearer JWT `role=admin` + `status=active` | Yes (true admin) |
| `X-ScooterCheck-Token` = `ADMIN_API_TOKEN` | Yes (`adminToken=True`) |
| Shared `API_TOKEN` + `API_TOKEN_GRANTS_ADMIN=1` | Legacy CRITICAL — **diagnostics MUST refuse** |
| `auth=open` (no secrets) | CRITICAL — **diagnostics MUST refuse** |

Ownership: `job_auth.py` (`is_admin`, `api_token_grants_admin`, `trust_api_token_client_id`).

### Deploy

`deploy/install-on-hetzner.sh`, `phase1-rollout.sh` (CONFIRM_PROD_DEPLOY gate), `scootercheck-fw.service`, nginx snippets, `set-anthropic-api-key.sh`.

### Existing API surface (unchanged)

Public: `/health`.  
User: `POST/GET /v1/firmware/jobs…` + artifact downloads.  
Admin: `/v1/firmware/admin/*` via `require_admin`.

---

## 2. Proposed endpoints

| Method | Path | Auth | Behavior |
|--------|------|------|----------|
| GET | `/v1/diagnostics/status` | `enforce_diagnostics_admin` | Safe probe assembly; grades per component; no secrets |
| POST | `/v1/diagnostics/selftest` | same | Single-flight + 30s soft rate limit; lightweight status/TEA/Ghidra hooks; 429 if busy |
| GET | `/v1/diagnostics/selftest/{job_id}` | same | Poll in-memory selftest job; opaque 404 |

### Grades

`CONFIGURED` ≠ `AVAILABLE` ≠ `VERIFIED` ≠ `FAILED` ≠ `UNKNOWN`  
Flags / path existence ⇒ at most **AVAILABLE**. **VERIFIED** only after B/C probe success.

### Wire note (PM)

```python
# wire in PM — do not merge until B/C + auth review
from diagnostics_routes import create_diagnostics_router
APP.include_router(create_diagnostics_router(require_auth=require_auth))
```

`app.py` left untouched this cycle for Agent A.

---

## 3. New files

| File | Role |
|------|------|
| `server/firmware-analysis/diagnostics_models.py` | `DiagnosticGrade`, status + selftest pydantic models |
| `server/firmware-analysis/diagnostics_status.py` | Safe probes; auth posture; `assemble_diagnostics_status()` |
| `server/firmware-analysis/diagnostics_routes.py` | Router factory, auth gate, selftest single-flight / rate notes |
| `research/cycle11/agent_a/REPORT_SERVER_DIAGNOSTICS.md` | This report |

Optional hooks (lazy ImportError → existence-only steps):

- `diagnostics_tea.run_tea_selftest` (Agent B)
- `diagnostics_ghidra.run_ghidra_selftest` (Agent C)

---

## 4. Reuse list

- `/health` flag vocabulary (`decryptConfigured`, `ghidraConfigured`, auth booleans) — extended as graded components, never secrets
- `job_auth.api_token_grants_admin` / `trust_api_token_client_id`
- `ghidra_decompile.ghidra_configured`
- `llm_enrich.llm_configured` / `llm_key_status` (kind only)
- `r2_extract` / `capstone_extract` / `yara_scan` / `unicorn_emulate` / `angr_lite` `*_configured`
- Deploy tree presence check under `deploy/`
- Cycle 9/10 synthetic Ghidra fixtures (for Agent C VERIFIED — not executed here)
- `_HEAVY_ANALYSIS_LOCK` single-flight semantics (documented for selftest vs prod Ghidra)

---

## 5. Auth gate rule

```
diagnostics_allowed ⇔ authMode == "separated"
                   ⋀ (ADMIN_API_TOKEN set ∨ JWT_SECRET set)

caller_allowed ⇔ (auth == jwt ∧ role == admin)
               ∨ (auth == api_token ∧ adminToken == true)

REFUSE if authMode ∈ {open, shared_token_admin}
REFUSE if caller is shared API_TOKEN without adminToken
NEVER accept privilege solely via apiTokenGrantsAdmin
```

`app.require_admin` / `job_auth.is_admin` remain too weak for diagnostics when grants=1 — use `enforce_diagnostics_admin` instead.

---

## 6. Rate limit / single-flight

Documented + lightly enforced in `diagnostics_routes.py`:

- Process-wide `_SELFTEST_LOCK` + `_ACTIVE_SELFTEST_ID` → HTTP 429 if busy
- Soft create interval `_MIN_SELFTEST_INTERVAL_SEC = 30` → HTTP 429
- Suggest nginx `limit_req` on `/v1/diagnostics/`
- Avoid overlapping heavy Ghidra selftest with prod jobs on ≤4 GB hosts

---

## 7. Residual / handoff

| Item | Owner |
|------|-------|
| Wire router into `app.py` | PM |
| TEA decrypt fixture VERIFIED | Agent B (`diagnostics_tea.py`) |
| Ghidra headless fixture VERIFIED | Agent C (`diagnostics_ghidra.py`) |
| iOS Diagnostics client | Agent D |
| Live Hetzner apply | Ops + Freigabe (CONFIRM_PROD_DEPLOY) |

Local smoke (this Cloud VM): modules import; open/shared-user/grants=1 refused; JWT admin + ADMIN_API_TOKEN accepted; router paths registered. pydantic/fastapi installed ad hoc for smoke — not committed.
