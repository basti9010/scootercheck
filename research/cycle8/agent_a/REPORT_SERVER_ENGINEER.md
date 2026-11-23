# Cycle 8 AGENT A – Server Engineer Inventory

**Date:** 2026-11-23 (Europe/Berlin)  
**Branch:** `cursor/server-engineer-inventory-b100`  
**Base:** `cursor/server-deploy-ghidra-ios-c8-b100` @ `00560d0`  
**Scope:** Existing FastAPI firmware-analysis server at `server/firmware-analysis/` (Cycle 7 port).  
**Hard bans observed:** no second architecture invented; no credentials invented; no production settings changed; no secrets committed; `CONFIRM_PROD_DEPLOY` left unset.

---

## Verdict (short)

In-tree server is a single FastAPI worker (`app.py` v1.5.0) with documented Hetzner deploy under `deploy/`. NinebotTEA is integrated **only** via external `DECRYPT_CMD` (wrapper → `ninebottea`); binary/keys are **not** in the repo.  

**Host reachability:** public HTTPS `/health` on the documented App URL responds; **SSH to the Hetzner host from this Cloud VM is not possible** (`~/.ssh/hetzner_scootercheck` missing → `Permission denied (publickey,password)`).

---

## 1. Deployment config (`server/firmware-analysis/deploy/`)

### Scripts / units found

| Path | Role |
|------|------|
| `deploy/install-on-hetzner.sh` | On-host bootstrap: user `scootercheck`, dirs, venv (Python 3.12), copy ninebottea into venv if `NINEBOTTEA_SRC` present, install systemd + nginx snippet, enable `scootercheck-fw` |
| `deploy/phase1-rollout.sh` | Remote rollout via SSH/rsync; **default DRY-RUN**; live only if `CONFIRM_PROD_DEPLOY=YES` |
| `deploy/scootercheck-fw.service` | systemd unit: uvicorn `127.0.0.1:8088`, `EnvironmentFile=/etc/scootercheck/firmware-analysis.env`, hardened (`ProtectSystem=strict`, `ProtectHome=true`, …) |
| `deploy/nginx-scootercheck-fw.conf` | nginx snippet: `location /scootercheck-fw/` → `http://127.0.0.1:8088/`, `client_max_body_size 80m`, timeouts 300s |
| `deploy/nginx-fw.conf.example` | Standalone TLS server example (placeholder hostname) |
| `deploy/set-anthropic-api-key.sh` | Ops helper to set `LLM_API_KEY` on the host without echoing the key (runs on Hetzner) |

Also related (not under `deploy/`): `decrypt-firm.example.sh` → installed as `/opt/scootercheck/decrypt-firm.sh` by install script.

### Documented production layout (from scripts/README — not invented)

| Item | Path / value |
|------|----------------|
| App dir | `/opt/scootercheck/firmware-analysis` |
| Env file | `/etc/scootercheck/firmware-analysis.env` |
| Decrypt wrapper | `/opt/scootercheck/decrypt-firm.sh` |
| Decrypt env (KEY/VARIANT — not in git) | `/etc/scootercheck/decrypt.env` |
| Jobs / plaintext / decompile / stock | `/var/lib/scootercheck/{firmware-jobs,decrypted,decompiled,stock-fw}` |
| Ghidra | `/opt/ghidra` |
| Public URL (App default) | `https://api.tuningscanner.de/scootercheck-fw` |
| Rollout SSH default | `REMOTE_HOST=root@api.tuningscanner.de`, `SSH_IDENTITY=$HOME/.ssh/hetzner_scootercheck` |

`phase1-rollout.sh` never touches `/var/lib/scootercheck` data; syncs a fixed file list (Python modules, Ghidra scripts, docs, tests). Dry-run with `CONFIRM_PROD_DEPLOY` unset is the safe default.

---

## 2. Python env / requirements

**File:** `requirements.txt`

| Package | Pin |
|---------|-----|
| fastapi | 0.115.6 |
| uvicorn[standard] | 0.32.1 |
| python-multipart | 0.0.17 |
| pydantic | 2.10.3 |
| PyJWT | 2.10.1 |
| capstone | 5.0.3 |
| yara-python | 4.5.1 |
| unicorn | 2.1.1 |
| angr | **not pinned** — optional; comment says install manually; `angr_lite` falls back to Capstone |

**Install story (`install-on-hetzner.sh`):**

- `python3.12 -m venv .venv` under app dir (avoids Python 3.14 wheel gaps)
- `pip install -r requirements.txt`
- `apt-get install … radare2`
- Optional: copy host `ninebottea` site-packages into venv (`NINEBOTTEA_SRC` / default under `/root/ninebottea/…`)

**This Cloud VM:** no project `.venv`; `fastapi` not installed globally; `GHIDRA_HOME` / `DECRYPT_CMD` unset; `/opt/ghidra` and `/opt/scootercheck` absent.

---

## 3. API endpoints (`app.py`)

FastAPI app: `APP` title `ScooterCheck Firmware Analysis`, version `1.5.0`.

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | open |
| POST | `/v1/firmware/jobs` | `require_auth` (multipart: `meta_json` + `archive`) |
| GET | `/v1/firmware/jobs/{job_id}` | auth + job ownership |
| GET | `/v1/firmware/jobs/{job_id}/plaintext` | same |
| GET | `/v1/firmware/jobs/{job_id}/decompile` | same |
| GET | `/v1/firmware/jobs/{job_id}/functions` | same |
| GET | `/v1/firmware/jobs/{job_id}/callgraph` | same |
| GET | `/v1/firmware/jobs/{job_id}/function-diff` | same |
| GET | `/v1/firmware/jobs/{job_id}/input-behavior` | same |
| GET | `/v1/firmware/jobs/{job_id}/input-behavior-diff` | same |
| GET | `/v1/firmware/jobs/{job_id}/activation-forensics` | same |
| GET | `/v1/firmware/jobs/{job_id}/semantic-dataflow` | same |
| GET | `/v1/firmware/admin/jobs` | `require_admin` |
| GET | `/v1/firmware/admin/stats` | admin |
| GET/POST | `/v1/firmware/admin/stock` | admin |
| DELETE | `/v1/firmware/admin/stock/{ref_id}` | admin |
| POST | `/v1/firmware/admin/jobs/{job_id}/promote-stock` | admin |
| GET | `/v1/firmware/admin/reference-catalogs` | admin |
| GET | `/v1/firmware/admin/reference-inventory` | admin |
| POST | `/v1/firmware/admin/reference-catalogs/batch-test` | admin |
| POST | `/v1/firmware/admin/reference-catalogs/build` | admin |
| DELETE | `/v1/firmware/admin/jobs/{job_id}` | admin |

`JobRequestMeta`: `clientReportId`, `originalFileName`, `archiveSHA256`, `payloadSHA256?`, `infoJSON?`, `models[]`, `controllerType?`, `allowDecrypt` (default true), `allowLLM` (default false).

Pipeline after submit: `BackgroundTasks` → `process_job` (extract → decrypt/plaintext → r2 → Ghidra → Capstone → YARA → IVT → Unicorn → angr_lite → limit_slice → input_probe → stock_diff → function/callgraph/diff → input behavior / activation / semantic dataflow → optional LLM).

---

## 4. NinebotTEA / `DECRYPT_CMD` integration

| Layer | Status | Evidence |
|-------|--------|----------|
| App hook | **SUPPORTED** (code) | `DECRYPT_CMD` env; `run_decrypt()` runs `[DECRYPT_CMD, enc, out]` timeout 120s |
| Wrapper | **SUPPORTED** (example in repo) | `decrypt-firm.example.sh`: `ninebottea decrypt … --variant tea\|xtea`; auto tea then xtea; optional `KEY`/`VARIANT` from `/etc/scootercheck/decrypt.env` |
| Package in git | **UNSUPPORTED** | README: repo ships neither ninebottea nor keys |
| Install path | Documented only | Copy into venv from host `NINEBOTTEA_SRC`; `NINEBOTTEA_BIN` in decrypt.env |
| Plaintext skip | **SUPPORTED** | `plaintext_detect.looks_like_plaintext_firmware` skips TEA; recovery on decrypt fail only with Cortex-M IVT |
| Live decrypt from this VM | **NOT_TESTED** | no binary, no `DECRYPT_CMD`, no SSH |
| Prod `decryptConfigured` | `true` (health) | means env path set — **not** proof of TEA/XTEA success rates |

No decrypt keys were present or requested; none invented.

---

## 5. Supported file formats

**Uploads (`extract_enc_payload` + `zip_safe`):**

| Input | Behavior |
|-------|----------|
| `.zip` | Must contain `FIRM.bin.enc` / `*.bin.enc` / any `*.enc`; optional `info.json` (≤2 MiB); zip-bomb / traversal / symlink guards |
| Bare `.enc` / other suffix | Copied as enc payload path |
| Size | Default max upload **80 MiB** (`FW_MAX_UPLOAD_BYTES`); nginx snippet also `client_max_body_size 80m` |

**Post-extract:**

| Case | Behavior |
|------|----------|
| Filename / IVT / soft entropy → plaintext | Skip ninebottea; copy through |
| Encrypted | `DECRYPT_CMD` (tea→xtea in example wrapper) |
| Decrypt fail + IVT recovery | May treat as plaintext (`cortex_m_ivt` only) |
| `allowDecrypt=false` | `DECRYPT_NOT_ALLOWED` |
| BLE RAW4TFT magic | `ble_container.identify_ble_container` (container ID; does not decrypt) |
| Non-RAW4TFT BLE path | `FORMAT_UNSUPPORTED` for that identifier only |

---

## 6. Analysis workers

| Worker | Module | Gate | Notes |
|--------|--------|------|-------|
| Ghidra Headless | `ghidra_decompile.py` + `ghidra_scripts/*.java` | `ENABLE_GHIDRA`, `ghidra_configured()` (`GHIDRA_HOME` / `GHIDRA_HEADLESS` / `/opt/ghidra/…`) | Exports `.c`, speeds, limits, functions, callgraph, dataflow; serialized via `_HEAVY_ANALYSIS_LOCK` |
| radare2 | `r2_extract.py` | `ENABLE_R2`, `r2` on PATH | Packed speed `/x` + `izz` strings |
| Capstone | `capstone_extract.py` | `ENABLE_CAPSTONE`, import `capstone` | ARM/Thumb immediates |
| YARA | `yara_scan.py` | `ENABLE_YARA`, `yara_rules/scooter_cfw.yar` | CFW / panic / region hints |
| Unicorn | `unicorn_emulate.py` | `ENABLE_UNICORN`, import `unicorn` | Short windows around speed sites + optional Reset boot |
| angr / angr_lite | `angr_lite.py` + `angr_cfg_worker.py` | Capstone for lite; `ENABLE_ANGR` + import `angr` for CFGFast subprocess | RAM/timeout caps (`ANGR_MEM_MB`, `ANGR_TIMEOUT_SEC`); shares heavy lock with Ghidra |
| Limit slice / input probe | `limit_slice.py`, `input_probe.py` | `ENABLE_LIMIT_SLICE`, `ENABLE_INPUT_PROBE` | Capstone + Unicorn heuristics |
| Stock diff / catalogs | `stock_diff.py`, `reference_catalog.py` | `STOCK_FW_DIR` | OEM/serial refs only for trusted compare |
| LLM enrich | `llm_enrich.py` | `allowLLM` + `LLM_API_KEY` | Opt-in; schema-bound |

---

## 7. Job file storage paths

Defaults from `.env.example` / install script (prod):

```text
WORK_DIR=/var/lib/scootercheck/firmware-jobs
PLAINTEXT_STORE=/var/lib/scootercheck/decrypted
DECOMPILE_STORE=/var/lib/scootercheck/decompiled
STOCK_FW_DIR=/var/lib/scootercheck/stock-fw
```

**Per-job layout:**

```text
WORK_DIR/YYYY/MM/DD/<jobId>/
  upload/<originalName>
  request.json
  status.json          # source of truth across restarts
  FIRM.bin.enc         # extracted payload
  FIRM.dec.bin         # plaintext in job dir
  FIRM.dec.c / FIRM.limits.c / FIRM.functions.json / FIRM.callgraph.json …
PLAINTEXT_STORE/YYYY/MM/DD/<jobId>_<sha12>_<name>.dec.bin
DECOMPILE_STORE/YYYY/MM/DD/<jobId>_<sha12>_<name>.dec.c (+ .speeds.json, .limits.c, …)
```

Retention: `JOB_RETENTION_DAYS` (default 30), `MAX_STORED_JOBS` (default 500); `cleanup_old_jobs()` on submit/admin list.

Local/dev fallback when env unset: temp dirs under `tempfile.gettempdir()`.

---

## 8. Auth (API token + JWT)

Implemented in `app.py::require_auth` + `job_auth.py` (Phase 2.1 / 2.2B / 2.2H / 2.2H.1 / 2.2H.2).

| Mechanism | Header / claim | Behavior |
|-----------|----------------|----------|
| Bearer JWT | `Authorization: Bearer …` | Same `JWT_SECRET`/`JWT_ALGORITHM` (HS256) as ScooterCheck Auth; `status=active`; owner `user:<sub>`; preferred when both JWT and token sent |
| Shared API token | `X-ScooterCheck-Token` = `API_TOKEN` | Authenticates request; **not** admin by default (`API_TOKEN_GRANTS_ADMIN=0`) |
| Admin API token | `X-ScooterCheck-Token` = `ADMIN_API_TOKEN` | Admin endpoints |
| Client id | `X-ScooterCheck-Client-Id` | Metadata only unless legacy `TRUST_API_TOKEN_CLIENT_ID=1` |
| Open | none configured | Dev only when no `API_TOKEN` / `ADMIN_API_TOKEN` / `JWT_SECRET` |
| Denied job | — | Opaque **404** |

Secure defaults in `.env.example`: `API_TOKEN_GRANTS_ADMIN=0`, `TRUST_API_TOKEN_CLIENT_ID=0`.

**Public `/health` observation (2026-11-23, no credentials):** `apiTokenGrantsAdmin: true`, `adminApiTokenConfigured: false`. Response lacked `authSecurityOk` / `authSecurityWarnings` / `trustApiTokenClientId` present in **current** `app.py` — suggests production revision may lag the in-tree Phase 2.2H.2 health fields. **No settings were changed.**

---

## 9. Logging

| Layer | What exists |
|-------|-------------|
| Application | **No** `logging` / `getLogger` usage in `app.py`. Progress/state written to `status.json` (`message`, `state`, `progressPercent`, `notes` inside result). |
| Process | systemd runs uvicorn; stdout/stderr → journal for `scootercheck-fw` (unit has no custom `StandardOutput=`). |
| Decrypt wrapper | stderr on failure; temporary `.err` beside output during attempts. |
| Health | Operational flags only (no secret values). |

There is no separate structured log file path configured in-repo.

---

## 10. Access rights / Hetzner reachability

### Checks performed (safe only)

| Check | Result |
|-------|--------|
| `~/.ssh/` | **Missing** (no directory) |
| `~/.ssh/hetzner_scootercheck` | **Missing** |
| `CONFIRM_PROD_DEPLOY` | unset → rollout dry-run mode |
| DNS `api.tuningscanner.de` | Resolves (public A record observed) |
| SSH `root@api.tuningscanner.de` BatchMode | `Permission denied (publickey,password)` — Identity file not accessible |
| `GET https://api.tuningscanner.de/scootercheck-fw/health` | HTTP **200**, `ok: true`, `service: scootercheck-fw` |
| Local `/opt/scootercheck`, `/opt/ghidra`, decrypt.env | **Absent** on this VM |
| `phase1-rollout.sh` dry-run | Started DRY-RUN; local unittest aborted (`ModuleNotFoundError: fastapi`) — no remote writes |

### Verdict

**NO ACCESS TO HETZNER HOST FROM THIS ENVIRONMENT** (no SSH key; cannot install, restart, or read host env/files).

Network can **read** the public reverse-proxied `/health` endpoint only. That proves the App URL’s firmware worker is up from the internet; it does **not** grant host admin access or TEA decrypt capability on this VM.

### Selected public health flags (non-secret)

| Flag | Value |
|------|-------|
| decryptConfigured | true |
| ghidraConfigured / ghidraEnabled | true / true |
| jwtConfigured / apiTokenConfigured | true / true |
| adminApiTokenConfigured | false |
| apiTokenGrantsAdmin | true |
| r2 / capstone / yara / unicorn | true |
| angrLite / angrEngine | true / true |
| llmConfigured / provider | true / anthropic |
| stockRefCount | 42 |
| retentionDays / maxStoredJobs | 30 / 500 |

---

## Phase-4 TEA grades (evidence only)

Grades: **SUPPORTED** / **UNSUPPORTED** / **NOT_TESTED** / **UNKNOWN**

| Item | Grade | Basis |
|------|-------|-------|
| `DECRYPT_CMD` integration in FastAPI | **SUPPORTED** | `app.py` `run_decrypt` + pipeline |
| Wrapper CLI contract (`decrypt in out`, tea→xtea) | **SUPPORTED** | `decrypt-firm.example.sh` |
| ninebottea binary / keys in repository | **UNSUPPORTED** | README + install script (host-only) |
| TEA decrypt of real `.enc` on this Cloud VM | **NOT_TESTED** | no binary, no key, no SSH |
| XTEA fallback path in wrapper | **SUPPORTED** (code path) | example script `run_one tea \|\| run_one xtea` |
| Live TEA success rate on production | **UNKNOWN** | health only shows `decryptConfigured`; no job decrypt E2E from here |
| Whether prod `decrypt.env` has `KEY` / fixed `VARIANT` | **UNKNOWN** | host file not readable without SSH |
| Plaintext skip / IVT recovery (no TEA) | **SUPPORTED** | `plaintext_detect.py` + `process_job` |

---

## Deploy scripts list (return artifact)

1. `server/firmware-analysis/deploy/install-on-hetzner.sh`  
2. `server/firmware-analysis/deploy/phase1-rollout.sh`  
3. `server/firmware-analysis/deploy/scootercheck-fw.service`  
4. `server/firmware-analysis/deploy/nginx-scootercheck-fw.conf`  
5. `server/firmware-analysis/deploy/nginx-fw.conf.example`  
6. `server/firmware-analysis/deploy/set-anthropic-api-key.sh`  

Related decrypt example (not under `deploy/`): `server/firmware-analysis/decrypt-firm.example.sh`

---

## Gaps / next ops (not executed)

1. Provide SSH identity only via secure ops channel if Cycle 8 needs host deploy — **not** available in this Cloud Agent env.  
2. Align prod auth flags with Phase 2.2H.2 (`ADMIN_API_TOKEN`, `API_TOKEN_GRANTS_ADMIN=0`) — observed health still shows grants=true / no admin token flag; requires host ops, not this agent.  
3. Confirm deployed git tip vs in-tree health schema (missing `authSecurityOk` fields on live response).  
4. TEA E2E against authorized ENC samples only on host with ninebottea installed.

---

## Refs

- Tree: `server/firmware-analysis/`  
- Prior Cycle 7 inventory: `research/cycle7/agent_a/REPORT_SERVER_INFRA.md`  
- Kickoff: `research/cycle8/CYCLE8_KICKOFF.md`
