# Cycle 9 AGENT A – Server Validation

**Date:** 2026-11-23 (Europe/Berlin)  
**Branch:** `cursor/server-validation-c9-b100`  
**Base:** `cursor/prod-pipeline-forensic-c9-b100`  
**Scope:** Validate existing FastAPI firmware-analysis at `server/firmware-analysis/` (no second architecture, no production writes, no secrets invented/committed).

---

## Verdict

In-tree FastAPI worker (`app.py` v1.5.0) is **TESTED** locally for auth, job create/poll, background `process_job`, error codes, result delivery, ZIP safety, and storage layout using synthetic fixtures only.

Public App URL `/health` is **reachable** (read-only).  
**NO PROD ADMIN ACCESS** — `~/.ssh/hetzner_scootercheck` absent; no host shell, no write ops, no decrypt E2E on real ZT3 packs.

| Grade area | Status |
|------------|--------|
| API surface (code) | **IMPLEMENTED** |
| Auth / ownership (local) | **TESTED** |
| Job create + background process (synthetic) | **TESTED** |
| Result delivery / artifacts (local) | **TESTED** |
| Secure storage layout (local staging dirs) | **TESTED** |
| Production deploy / TEA decrypt E2E | **NOT claimable** (no admin access) |
| Production auth hardening vs in-tree | **GAP** (see residual) |

---

## 1. API endpoints

FastAPI `APP` title `ScooterCheck Firmware Analysis`, version `1.5.0`.

| Method | Path | Auth | Local check |
|--------|------|------|-------------|
| GET | `/health` | open | 200; flags only |
| POST | `/v1/firmware/jobs` | `require_auth` (multipart `meta_json` + `archive`) | queued → process |
| GET | `/v1/firmware/jobs/{id}` | auth + ownership | 200 owner / 404 foreign |
| GET | `/v1/firmware/jobs/{id}/plaintext` | same | 200 + bytes |
| GET | `/v1/firmware/jobs/{id}/decompile` | same | 401/404 gated |
| GET | `/v1/firmware/jobs/{id}/functions` | same | gated |
| GET | `/v1/firmware/jobs/{id}/callgraph` | same | gated |
| GET | `/v1/firmware/jobs/{id}/function-diff` | same | gated |
| GET | `/v1/firmware/jobs/{id}/input-behavior` | same | gated |
| GET | `/v1/firmware/jobs/{id}/input-behavior-diff` | same | gated |
| GET | `/v1/firmware/jobs/{id}/activation-forensics` | same | gated |
| GET | `/v1/firmware/jobs/{id}/semantic-dataflow` | same | gated |
| GET | `/v1/firmware/admin/jobs` | `require_admin` | 401/403/200 |
| GET | `/v1/firmware/admin/stats` | admin | 401/403/200 |
| GET/POST | `/v1/firmware/admin/stock` | admin | GET gated |
| DELETE | `/v1/firmware/admin/stock/{ref_id}` | admin | (code reviewed) |
| POST | `/v1/firmware/admin/jobs/{id}/promote-stock` | admin | (code reviewed) |
| GET | `/v1/firmware/admin/reference-catalogs` | admin | gated |
| GET | `/v1/firmware/admin/reference-inventory` | admin | gated |
| POST | `/v1/firmware/admin/reference-catalogs/batch-test` | admin | (code reviewed) |
| POST | `/v1/firmware/admin/reference-catalogs/build` | admin | (code reviewed) |
| DELETE | `/v1/firmware/admin/jobs/{id}` | admin | (code reviewed) |

`JobRequestMeta`: `clientReportId`, `originalFileName`, `archiveSHA256`, `payloadSHA256?`, `infoJSON?`, `models[]`, `controllerType?`, `allowDecrypt` (default true), `allowLLM` (default false).

---

## 2. Auth (token / JWT)

| Mechanism | Behavior |
|-----------|----------|
| Bearer JWT | Preferred when present; requires `JWT_SECRET`; `status=active`; `sub` → `user:<sub>` owner |
| `X-ScooterCheck-Token` = `ADMIN_API_TOKEN` | Admin |
| `X-ScooterCheck-Token` = `API_TOKEN` | Authenticated; **not** admin unless `API_TOKEN_GRANTS_ADMIN=1` (default **0**) |
| `X-ScooterCheck-Client-Id` | Metadata only by default; ownership only if `TRUST_API_TOKEN_CLIENT_ID=1` (default **0**) |
| Unauthorized job access | Opaque **404** (no metadata leak) |
| Dev open mode | Only if no API/ADMIN/JWT secrets configured |

Ownership helpers: `job_auth.py` (`resolve_owner_principal`, `can_access_job`, `require_job_access`).

`/health` exposes `jwtConfigured`, `apiTokenConfigured`, `adminApiTokenConfigured`, `apiTokenGrantsAdmin`, `trustApiTokenClientId`, `authSecurityOk`, `authSecurityWarnings` — **never secrets**.

---

## 3. Job creation

`POST /v1/firmware/jobs`:

1. Validate `meta_json` → 400 on bad JSON  
2. `cleanup_old_jobs()` (retention)  
3. Allocate `jobId` (UUID), day-structured dir `WORK_DIR/YYYY/MM/DD/<jobId>/`  
4. Size + ZIP safety (`zip_safe.validate_upload_size` / `inspect_zip`) → 400  
5. Persist upload + `request.json` + `status.json`  
6. Attach ownership fields from auth  
7. Return `state=queued` immediately  
8. Schedule `BackgroundTasks.add_task(process_job, job_id)`

Server computes `archiveSHA256` itself (client meta SHA is not trusted for integrity).

---

## 4. Background processing

`process_job(job_id)` (synchronous worker invoked by BackgroundTasks):

extract → plaintext detect / `DECRYPT_CMD` → store plaintext → optional r2 → Ghidra (serialized via `_HEAVY_ANALYSIS_LOCK`) → Capstone → YARA → IVT → Unicorn → angr_lite → limit_slice → input_probe → stock_diff → Phase-2 function/callgraph/diff → input behavior / activation / semantic dataflow → optional LLM (`allowLLM`) → `combo_policy` sanitize → `state=completed`.

Local validation drives `process_job` inline after POST (TestClient may also run BackgroundTasks). Ghidra/r2/angr disabled in staging harness; synthetic thumb `.dec.bin` completes via plaintext skip.

---

## 5. Error handling

| Condition | `errorCode` / HTTP | Local result |
|-----------|-------------------|--------------|
| Bad `meta_json` | HTTP 400 | **PASS** |
| Empty / oversized / unsafe ZIP | HTTP 400 | **PASS** (zip_safe + upload tests) |
| `allowDecrypt=false` | `DECRYPT_NOT_ALLOWED` | **PASS** |
| No enc payload | `NO_ENC_PAYLOAD` | (code path) |
| Decrypt fails / `DECRYPT_CMD` unset | `DECRYPT_FAILED` + partial `result` | **PASS** (synthetic `.enc`) |
| Missing/invalid JWT | HTTP 401 | **PASS** |
| Inactive account | HTTP 403 | **PASS** |
| Non-admin on admin routes | HTTP 403 | **PASS** |
| Foreign job / missing job | HTTP 404 | **PASS** |

Phase-2 / LLM / container steps use best-effort `try/except` so Phase-1 results can still complete.

**Residual bug (code):** when `ghidraImportAllowed is False` on a successful plaintext path, `process_job` hits `UnboundLocalError` at `result.setdefault(...)` **before** `result = deep_result(...)` (`app.py` ~780). Job can stick mid-flight. Reproduced locally with RAW4TFT + `.dec.bin` filename; **not fixed** this cycle (no production code change). Documented for follow-up.

---

## 6. Result delivery

- Poll: `GET /v1/firmware/jobs/{id}` → `job_status_payload` with `_sanitize_result_for_app(result)`  
- Artifacts: plaintext `FileResponse`; decompile file or preview JSON; full JSON for functions/callgraph/diff/input-behavior/activation/semantic-dataflow  
- Poll keeps summaries; heavy artifacts on disk under job dir / dated stores  
- Ownership enforced on every artifact GET  

Local: thumb fixture → `completed` + poll `result` + plaintext byte match; foreign JWT 404 on poll and plaintext.

---

## 7. Secure file storage

| Store | Default / prod path | Layout |
|-------|---------------------|--------|
| Jobs | `WORK_DIR` → `/var/lib/scootercheck/firmware-jobs` | `YYYY/MM/DD/<jobId>/{upload,status.json,request.json,...}` |
| Plaintext | `PLAINTEXT_STORE` → `.../decrypted` | `YYYY/MM/DD/<jobId>_<sha12>_*.dec.bin` |
| Decompile | `DECOMPILE_STORE` → `.../decompiled` | dated `.c` / `.json` sidecars |
| Stock | `STOCK_FW_DIR` → `.../stock-fw` | admin-managed refs |

Controls: upload size (80 MiB default, matches nginx `client_max_body_size 80m`), ZIP traversal/symlink/bomb guards, retention `JOB_RETENTION_DAYS=30`, soft cap `MAX_STORED_JOBS=500`, systemd `ProtectSystem=strict` / `ReadWritePaths` limited to scootercheck dirs.

Local staging uses isolated temp trees via `staging_harness.py` (never `/var/lib/scootercheck`).

---

## 8. Server configuration

| Item | Source |
|------|--------|
| Env example | `.env.example` (placeholders only) |
| systemd | `deploy/scootercheck-fw.service` — uvicorn `127.0.0.1:8088`, `EnvironmentFile=/etc/scootercheck/firmware-analysis.env` |
| nginx | `deploy/nginx-scootercheck-fw.conf` — `/scootercheck-fw/` → backend, 80m body, 300s timeouts |
| Install / rollout | `install-on-hetzner.sh`, `phase1-rollout.sh` (default dry-run; live needs `CONFIRM_PROD_DEPLOY=YES`) |
| Decrypt | External `DECRYPT_CMD` only; keys **not** in repo |
| Public App URL | `https://api.tuningscanner.de/scootercheck-fw` |

This Cloud VM: light deps installed for tests (`fastapi`, `PyJWT`, `httpx`, …); `capstone` / `yara` / `unicorn` / `angr` / Ghidra **not** required for the validation suite (optional stages skip).

---

## Local integration tests

**Command (from `server/firmware-analysis/`):**

```bash
python3 -m unittest \
  test_cycle9_server_validation \
  test_api_auth_security test_job_auth test_zip_safe \
  test_upload_integrity_sha256 test_plaintext_detect \
  test_phase22h_e2e test_phase22h2_jwt_e2e -v
```

| Suite | Result |
|-------|--------|
| `test_cycle9_server_validation` (new) | **14 / 14 OK** |
| Combined validation set above | **104 ran, 0 fail, 2 skipped** (unicorn missing; ghidra not configured) |

Synthetic only: `testdata/thumb_validation/bin/version_a.bin`, high-entropy fake `.enc`, ZIP bomb probe. **No real ZT3 decrypt.**

---

## Production `/health` probe (read-only)

`GET https://api.tuningscanner.de/scootercheck-fw/health` → **HTTP 200**

| Flag | Observed (no secrets) |
|------|------------------------|
| `ok` | `true` |
| `service` | `scootercheck-fw` |
| `decryptConfigured` | `true` |
| `ghidraConfigured` / `ghidraEnabled` | `true` / `true` |
| `jwtConfigured` / `apiTokenConfigured` | `true` / `true` |
| `adminApiTokenConfigured` | **`false`** |
| `apiTokenGrantsAdmin` | **`true`** (insecure vs in-tree default) |
| `authSecurityOk` / `trustApiTokenClientId` / `authSecurityWarnings` | **absent** (prod revision lags Phase 2.2H.2 health fields) |
| `llmConfigured` | `true` (`llmKeyStatus.usable=true`, kind anthropic-usr — no key material) |
| `stockRefCount` | `42` |
| `r2` / `capstone` / `yara` / `unicorn` / `angr*` | configured flags true |

**NO PROD ADMIN ACCESS** — cannot verify systemd unit, env file contents, TEA success rate, or apply config fixes from this environment.

---

## Residual gaps

1. **Prod auth posture:** `apiTokenGrantsAdmin=true` and no dedicated admin token on live `/health`; in-tree secure defaults differ. Needs host ops with admin access.  
2. **Prod code lag:** missing `authSecurityOk` / `trustApiTokenClientId` on live health → deploy of current tree not confirmed.  
3. **`UnboundLocalError` on Ghidra-blocked plaintext path** (`app.py` ~780) — local repro; fix deferred (no production change this agent).  
4. **TEA / Ghidra E2E on production:** UNKNOWN (decryptConfigured/ghidraConfigured only).  
5. **Heavy optional deps** on this VM: capstone/yara/unicorn/angr/Ghidra skipped; not a product gap.  
6. No SSH identity → cannot inspect `/etc/scootercheck/*.env`, retention on disk, or nginx live config beyond public health.

---

## Deliverables

| Path | Role |
|------|------|
| `server/firmware-analysis/test_cycle9_server_validation.py` | Cycle 9 local integration tests |
| `research/cycle9/agent_a/REPORT_SERVER_VALIDATION.md` | This report |

Constraints honored: no second architecture, no prod writes, no secrets committed, no real ZT3 pack decrypt.
