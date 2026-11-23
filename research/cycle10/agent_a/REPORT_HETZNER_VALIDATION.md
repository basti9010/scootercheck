# Cycle 10 AGENT A – Hetzner Server Validation

**Date:** 2026-11-23T20:48:22Z (UTC)  
**Branch:** `cursor/hetzner-validation-agent-a-b100`  
**Base:** `cursor/hetzner-ghidra-live-c10-b100` @ `3d513db`  
**Scope:** Existing FastAPI firmware-analysis (`server/firmware-analysis/`) Hetzner readiness — deploy, Python env, NinebotTEA/`DECRYPT_CMD`, Ghidra, API config, workers, permissions, auth, analysis dirs.  
**Hard bans observed:** no credentials invented/stored; no production changes; `CONFIRM_PROD_DEPLOY` left unset; no auth bypass; no second architecture.

Evidence class on every finding: **LIVE** = probed this Cloud VM / public endpoint this run; **REPO** = derived from git files only.

---

## Access verdict

**NO HETZNER HOST ACCESS from this environment.**

| Capability | Result |
|------------|--------|
| Host shell / systemd / env files | **Blocked** — no SSH identity |
| Real deploy / restart | **Blocked** |
| TEA / Ghidra job E2E on production | **Not claimable** |
| Public App URL `/health` (read-only) | **Reachable** |

### Exact SSH blocker (LIVE)

1. `~/.ssh/` directory **absent** on this Cloud VM.  
2. Default identity `~/.ssh/hetzner_scootercheck` **absent** (`No such file or directory`).  
3. `ssh -o BatchMode=yes -i ~/.ssh/hetzner_scootercheck root@api.tuningscanner.de`:  
   - Warning: Identity file not accessible  
   - `Permission denied (publickey,password)`  
4. Without that key (or an equivalent authorized identity), Agent A cannot inspect `/etc/scootercheck/*.env`, `/opt/scootercheck`, `/opt/ghidra`, journalctl, or run on-host TEA/Ghidra validation.

Public HTTPS health proves the reverse-proxied worker is up; it does **not** grant host admin or decrypt execution proof.  
`ghidraConfigured=true` / `decryptConfigured=true` alone are **NOT** execution proof.

---

## LIVE vs REPO findings table

| Finding | Class | Detail |
|---------|-------|--------|
| `~/.ssh/` / `hetzner_scootercheck` | **LIVE** | Both absent |
| SSH BatchMode to `root@api.tuningscanner.de` | **LIVE** | `Permission denied (publickey,password)` |
| DNS `api.tuningscanner.de` | **LIVE** | `77.42.19.224` |
| `GET https://api.tuningscanner.de/scootercheck-fw/health` | **LIVE** | HTTP 200, `ok:true`, nginx/1.28.3 |
| `CONFIRM_PROD_DEPLOY` unset → dry-run | **LIVE** | Script set `DRY_RUN=1`, logged `mode=DRY-RUN` |
| Dry-run remote writes | **LIVE** | None — aborted at local unit tests before `preflight_ssh` |
| Local `fastapi` / project `.venv` | **LIVE** | Missing (`ModuleNotFoundError: fastapi`); no `.venv` |
| `GHIDRA_HOME` / `DECRYPT_CMD` on this VM | **LIVE** | Unset |
| `/opt/scootercheck`, `/opt/ghidra` on this VM | **LIVE** | Absent |
| Deploy scripts + systemd + nginx snippets | **REPO** | Under `deploy/` |
| Python deps / venv story | **REPO** | `requirements.txt` + `install-on-hetzner.sh` (Python 3.12) |
| `DECRYPT_CMD` / ninebottea hook | **REPO** | `app.py` + `decrypt-firm.example.sh`; binary/keys not in git |
| Ghidra headless integration | **REPO** | `ghidra_decompile.py`, `ghidra_scripts/*.java`, `_HEAVY_ANALYSIS_LOCK` |
| API routes / auth model | **REPO** | `app.py` + `job_auth.py` + `.env.example` |
| Analysis dir layout | **REPO** | `WORK_DIR` / `PLAINTEXT_STORE` / `DECOMPILE_STORE` / `STOCK_FW_DIR` |
| Prod auth lag vs in-tree health schema | **LIVE** + **REPO** | Live lacks `authSecurityOk` / `trustApiTokenClientId` / `authSecurityWarnings` present in current `app.py` |

---

## 1. Deploy scripts (REPO + LIVE dry-run)

### Inventory (REPO)

| Path | Role |
|------|------|
| `deploy/install-on-hetzner.sh` | On-host bootstrap: user `scootercheck`, dirs, Python 3.12 venv, optional ninebottea copy, systemd + nginx snippet |
| `deploy/phase1-rollout.sh` | SSH/rsync rollout; **default DRY-RUN**; live only if `CONFIRM_PROD_DEPLOY=YES` |
| `deploy/scootercheck-fw.service` | uvicorn `127.0.0.1:8088`, `EnvironmentFile=/etc/scootercheck/firmware-analysis.env`, hardened |
| `deploy/nginx-scootercheck-fw.conf` | `location /scootercheck-fw/` → backend; `client_max_body_size 80m`; timeouts 300s |
| `deploy/nginx-fw.conf.example` | Standalone TLS example |
| `deploy/set-anthropic-api-key.sh` | Ops helper for `LLM_API_KEY` on host |
| `decrypt-firm.example.sh` | Installed as `/opt/scootercheck/decrypt-firm.sh` by install script |

Documented defaults (REPO): `REMOTE_HOST=root@api.tuningscanner.de`, `SSH_IDENTITY=$HOME/.ssh/hetzner_scootercheck`, `REMOTE_APP=/opt/scootercheck/firmware-analysis`. Script never touches `/var/lib/scootercheck` data dirs on sync.

### Dry-run this session (LIVE)

```text
CONFIRM_PROD_DEPLOY unset → CONFIRM_PROD_DEPLOY=NO → DRY_RUN=1
[fw-rollout] mode=DRY-RUN (set CONFIRM_PROD_DEPLOY=YES for real deploy)
require_local_files → OK
run_local_tests → FAIL (fastapi missing; 3 unrelated assertion fails when modules load)
→ die 'local unit tests failed — aborting before any remote change'
```

**No** `preflight_ssh`, **no** rsync, **no** restart. Safe abort before any remote contact for deploy.

---

## 2. Python environment

| Item | Class | Status |
|------|-------|--------|
| Pins | **REPO** | fastapi 0.115.6, uvicorn 0.32.1, multipart, pydantic, PyJWT, capstone, yara-python, unicorn; angr optional/unpinned |
| Host install | **REPO** | `python3.12 -m venv .venv` under app dir; `pip install -r requirements.txt`; apt `radare2` |
| This Cloud VM | **LIVE** | Python 3.12.3 system; no project venv; fastapi not installed; dry-run tests fail closed |

---

## 3. NinebotTEA / `DECRYPT_CMD`

| Layer | Grade | Class | Basis |
|-------|-------|-------|-------|
| FastAPI hook `run_decrypt([DECRYPT_CMD, enc, out])` | **SUPPORTED** | **REPO** | `app.py` timeout 120s |
| Wrapper contract tea→xtea | **SUPPORTED** | **REPO** | `decrypt-firm.example.sh` |
| ninebottea binary / keys in git | **UNSUPPORTED** | **REPO** | README + install (host-only; `NINEBOTTEA_SRC`) |
| TEA decrypt of real `.enc` on this VM | **NOT_TESTED** | **LIVE** | no binary, `DECRYPT_CMD` unset, no SSH |
| Production decrypt success rate | **UNKNOWN** | **LIVE** | `/health` only shows `decryptConfigured: true` (path set ≠ success) |
| Prod `decrypt.env` KEY/VARIANT contents | **UNKNOWN** | — | host file not readable without SSH |
| Plaintext skip / IVT recovery | **SUPPORTED** | **REPO** | `plaintext_detect` + pipeline |

Install story (REPO): `DECRYPT_CMD=/opt/scootercheck/decrypt-firm.sh`; `/etc/scootercheck/decrypt.env` (mode 640, `root:scootercheck`); optional copy of host ninebottea into venv.

---

## 4. Ghidra

| Layer | Grade | Class | Basis |
|-------|-------|-------|-------|
| Headless detection (`GHIDRA_HOME` / `GHIDRA_HEADLESS` / `/opt/ghidra/ghidra_*`) | **SUPPORTED** | **REPO** | `ghidra_decompile.ghidra_configured()` |
| Export scripts + pipeline lock | **SUPPORTED** | **REPO** | `ghidra_scripts/*.java`; `_HEAVY_ANALYSIS_LOCK` |
| systemd Java/Ghidra paths | **SUPPORTED** (declared) | **REPO** | `JAVA_HOME=…java-25…`; `ReadOnlyPaths=/opt/ghidra` |
| Headless on this Cloud VM | **NOT_TESTED** | **LIVE** | `GHIDRA_HOME` unset; `/opt/ghidra` absent |
| Production Ghidra job execution | **UNKNOWN** | **LIVE** | `ghidraConfigured/Enabled: true` only — not job E2E |

---

## 5. API configuration (REPO) + public health (LIVE)

App: FastAPI `ScooterCheck Firmware Analysis` **v1.5.0**.

| Method | Path | Auth (REPO) |
|--------|------|-------------|
| GET | `/health` | open |
| POST | `/v1/firmware/jobs` | `require_auth` |
| GET | `/v1/firmware/jobs/{id}` (+ artifacts) | auth + ownership |
| GET/POST/DELETE | `/v1/firmware/admin/*` | `require_admin` |

Public App URL (REPO + LIVE): `https://api.tuningscanner.de/scootercheck-fw`

### Public `/health` snapshot (LIVE, 2026-11-23, no credentials)

| Flag | Value |
|------|-------|
| `ok` / `service` | `true` / `scootercheck-fw` |
| `decryptConfigured` | `true` |
| `ghidraConfigured` / `ghidraEnabled` | `true` / `true` |
| `jwtConfigured` / `apiTokenConfigured` | `true` / `true` |
| `adminApiTokenConfigured` | **`false`** |
| `apiTokenGrantsAdmin` | **`true`** (insecure vs in-tree default `0`) |
| `authSecurityOk` / `trustApiTokenClientId` / `authSecurityWarnings` | **absent** |
| `llmConfigured` | `true` (`kind=anthropic-usr`, usable; no key material) |
| `stockRefCount` | `42` |
| `r2` / `capstone` / `yara` / `unicorn` / `angr*` | configured flags true |
| `retentionDays` / `maxStoredJobs` | `30` / `500` |

**Interpretation:** production revision likely **lags** in-tree Phase 2.2H.2 health fields. Auth posture on live still grants admin via shared API token without a dedicated admin token flag. **No settings were changed.**

---

## 6. Analysis workers (REPO; prod flags LIVE)

| Worker | Gate (REPO) | Prod flag (LIVE) |
|--------|-------------|------------------|
| Ghidra Headless | `ENABLE_GHIDRA`, `ghidra_configured()` | configured+enabled true |
| radare2 | `ENABLE_R2`, `r2` on PATH | `r2Configured: true` |
| Capstone | `ENABLE_CAPSTONE` | true |
| YARA | `ENABLE_YARA` | true |
| Unicorn | `ENABLE_UNICORN` | true |
| angr / angr_lite | Capstone lite; `ENABLE_ANGR` + angr for CFG | lite+engine true; timeout 150s; mem 1800 MB |
| Stock / catalogs | `STOCK_FW_DIR` | dir reported; 42 refs |
| LLM enrich | `allowLLM` + `LLM_API_KEY` | configured (anthropic) |

Heavy stages share `_HEAVY_ANALYSIS_LOCK` (REPO) for 4 GB VPS safety.

---

## 7. Permissions / analysis directories

### Documented layout (REPO)

```text
/opt/scootercheck/firmware-analysis          # app + .venv
/etc/scootercheck/firmware-analysis.env      # service env (600)
/etc/scootercheck/decrypt.env                # NINEBOTTEA_BIN / optional KEY (640 root:scootercheck)
/opt/scootercheck/decrypt-firm.sh
/opt/ghidra
/var/lib/scootercheck/firmware-jobs          # WORK_DIR YYYY/MM/DD/<jobId>/
/var/lib/scootercheck/decrypted              # PLAINTEXT_STORE
/var/lib/scootercheck/decompiled             # DECOMPILE_STORE
/var/lib/scootercheck/stock-fw               # STOCK_FW_DIR (+ catalogs)
```

systemd (REPO): `User=scootercheck`, `ProtectSystem=strict`, `ProtectHome=true`, `ReadWritePaths` limited to scootercheck paths, Ghidra/decrypt read-only.

On-host verification of ownership/modes: **UNKNOWN** (needs SSH) — **LIVE** blocker as above.

---

## 8. Auth (REPO vs LIVE)

| Mechanism | In-tree default (REPO) | Live signal (LIVE) |
|-----------|------------------------|--------------------|
| Bearer JWT (`JWT_SECRET`) | preferred user identity | `jwtConfigured: true` |
| `API_TOKEN` | auth, not admin (`API_TOKEN_GRANTS_ADMIN=0`) | configured; **`apiTokenGrantsAdmin: true`** |
| `ADMIN_API_TOKEN` | dedicated admin | **`adminApiTokenConfigured: false`** |
| `TRUST_API_TOKEN_CLIENT_ID` | `0` | field **absent** on live health |
| Job foreign access | opaque 404 | not E2E’d against prod |

Residual ops gap (not fixed this agent): align prod env with Phase 2.2H.2 secure defaults — requires host access / Freigabe.

---

## Grades summary (requested)

| Area | Grade |
|------|-------|
| NinebotTEA FastAPI integration | **SUPPORTED** |
| NinebotTEA binary/keys in repo | **UNSUPPORTED** |
| TEA decrypt E2E this VM | **NOT_TESTED** |
| TEA success on production | **UNKNOWN** |
| Ghidra code / deploy wiring | **SUPPORTED** |
| Ghidra headless this VM | **NOT_TESTED** |
| Ghidra job execution on production | **UNKNOWN** |

---

## Residual gaps (blocked on SSH / Freigabe)

1. Mount or inject `~/.ssh/hetzner_scootercheck` (or equivalent) into the Cloud Agent env for host validation.  
2. Confirm deployed tip vs in-tree (missing live `authSecurityOk` fields).  
3. Ops: set `ADMIN_API_TOKEN`, `API_TOKEN_GRANTS_ADMIN=0`, `TRUST_API_TOKEN_CLIENT_ID=0` on host — **not** done here.  
4. On-host TEA + Ghidra job E2E with authorized samples only.  
5. Local dry-run full path needs project deps installed before unit-test gate; even then SSH still blocks remote preflight.

---

## Constraints honored

- No inventing/storing secrets  
- No production changes (`CONFIRM_PROD_DEPLOY` unset)  
- No password guessing / auth bypass  
- Probes limited to: repo read, dry-run deploy, public GET `/health`, SSH key existence + BatchMode deny evidence  

## Refs

- Kickoff: `research/cycle10/CYCLE10_KICKOFF.md`  
- Prior: `research/cycle9/agent_a/REPORT_SERVER_VALIDATION.md`, `research/cycle8/agent_a/REPORT_SERVER_ENGINEER.md`  
- Tree: `server/firmware-analysis/`
