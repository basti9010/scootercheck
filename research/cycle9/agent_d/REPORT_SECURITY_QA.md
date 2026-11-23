# Cycle 9 AGENT D – Security & QA

**Stand:** 2026-11-23  
**Base:** `cursor/prod-pipeline-forensic-c9-b100`  
**Branch:** `cursor/security-qa-cycle9-b100`  
**Scope:** Highest-value confinement / ACL hardening in `server/firmware-analysis` (SMALL diffs; no prod secrets; no deploy)  
**Host:** Cloud Agent VM — **NOT DEPLOYED**; decrypt keys / Ghidra / Hetzner **NOT_TESTED**.

---

## Executive summary

Closed Cycle 8 Medium residual **S2** (plaintext/decompile download path confinement) plus related Low findings **S1/E1/E2/Z1** and Low **S3** (job-dir mode). Auth/ACL and upload/ZIP size gates remain solid. Process isolation (**I1**) stays **INCOMPLETE** here (needs host/systemd proof).

| # | Item | Cycle 8 | Cycle 9 | Notes |
|---|------|---------|---------|-------|
| 1 | Safe ZIP / path traversal | PASS (Low Z1) | **CLOSED Z1** | Backslash member names rejected |
| 2 | Plaintext-download confinement | Medium S2 open | **CLOSED S2** | Store-root + job-dir resolve checks |
| 3 | Upload size limits | PASS | PASS | Unchanged; regressions green |
| 4 | API auth + job ACL | PASS (Med A1) | PASS; **A1 warned** | Open-auth CRITICAL health warning |
| 5 | Secret handling | PASS | PASS | No secrets added; `.gitignore` retained |
| 6 | Process isolation | INCOMPLETE I1 | **OPEN / unfixable** | Documented; no nsjail/seccomp here |
| 7 | Unauthorized artifact access | PASS | PASS + hardened | ACL before confined FileResponse |
| 8 | Temp file storage | PASS (Low S3) | **mitigated S3** | `_secure_mkdir` → `0o750` |

---

## Pytest (this review)

Light deps: `fastapi`, `uvicorn`, `pydantic`, `PyJWT`, `httpx`, `python-multipart`, `pytest`.

```
78 passed (path confinement + zip + auth + job ACL + upload integrity + plaintext + JWT e2e)
```

Primary new suite: `test_path_confinement.py` (10 cases).

---

## Fixes implemented

### 1. Store-root path confinement — **S2 CLOSED** (Medium → fixed)

**Problem:** `download_plaintext` / `download_decompile` / stock promote used raw `Path(job["plaintextPath"])` from `status.json` with no store-root check (unlike `_job_artifact_path` for functions/callgraph).

**Fix:** `_confined_stored_file()` + `_is_path_under_root()`:

- Resolve candidate paths (symlink-safe).
- Allow only files under `PLAINTEXT_STORE` / `DECOMPILE_STORE` / `WORK_DIR` / job dir.
- Poisoned absolute paths and symlink escapes → opaque **404**.
- `delete_job_artifacts` also refuses to unlink outside known roots.

**Tests:** poisoned `/outside` paths, happy-path under store, symlink escape, promote path uses same helper.

### 2. Absolute path disclosure — **S1/E2 CLOSED** (Medium/Low → fixed)

**Problem:** Job poll payload and decompile preview returned absolute server paths.

**Fix:**

- `job_status_payload` returns **basename only** via `_client_safe_artifact_name` (keeps iOS non-empty path heuristics).
- Decompile preview JSON `path` field is basename only.

### 3. ZIP backslash traversal — **Z1 CLOSED** (Low → fixed)

`zip_safe._check_member_path` rejects any member name containing `\`, closing Windows-style `..\\..\\evil` that POSIX `Path.parts` does not split.

### 4. Generic JWT 401 — **E1 CLOSED** (Low → fixed)

`require_auth` returns `detail="invalid token"` without embedding PyJWT exception / algorithm hints.

### 5. Open-auth visibility — **A1 mitigated** (Medium residual ops)

`_auth_security_warnings` emits **CRITICAL** when `API_TOKEN`, `ADMIN_API_TOKEN`, and `JWT_SECRET` are all unset (`auth=open`). Health `authSecurityOk` stays false until secrets are set.

### 6. Job dir mode — **S3 mitigated** (Low)

`_secure_mkdir` applies `chmod 0o750` on new job/upload dirs (best-effort under umask).

---

## Residual risks (still open)

| Sev | ID | Item | Why open |
|-----|-----|------|----------|
| Medium | **I1** | Analyzer process isolation | Ghidra/r2/unicorn/angr share service UID; no seccomp/nsjail. **Unfixable** on this VM (no prod systemd / no analyzer binaries). Ops must verify unit hardening on Hetzner. |
| Medium | **A1** | Open-auth misdeploy | Code still allows `auth=open` for local/dev when all secrets unset. Health now CRITICAL-warns; production must set JWT + tokens + nginx bind. **NOT DEPLOY-VERIFIED**. |
| Low | **U1** | Upload memory buffer | Full body still read before size check; nginx `client_max_body_size` remains the edge mitigator. |
| Info | **I2** | angr default-on | Keep mem/timeout caps when package present. |

---

## Item checklist (Cycle 9 priorities)

| Priority | Status |
|----------|--------|
| 1 Safe ZIP / path traversal | **PASS** (Z1 closed) |
| 2 Plaintext-download path confinement | **PASS** (S2 closed) |
| 3 Upload size limits | **PASS** |
| 4 API auth + job ACL | **PASS** (A1 ops residual) |
| 5 Secret handling | **PASS** (no secrets in repo/diff) |
| 6 Process isolation | **INCOMPLETE / documented** |
| 7 Unauthorized artifact access | **PASS** |
| 8 Temp file storage | **PASS** (0o750 mkdir) |

---

## Files changed

| File | Change |
|------|--------|
| `server/firmware-analysis/app.py` | Confinement helpers; download/promote/delete; path sanitization; JWT detail; open-auth warning; secure mkdir |
| `server/firmware-analysis/zip_safe.py` | Reject `\` in ZIP member names |
| `server/firmware-analysis/test_path_confinement.py` | **New** — S1/S2/E1/E2/ACL/symlink/delete regressions |
| `server/firmware-analysis/test_zip_safe.py` | Backslash traversal case |
| `research/cycle9/agent_d/REPORT_SECURITY_QA.md` | This report |

---

## Severities closed / open

**Closed this cycle:** S2 (Medium), S1 (Medium), E1 (Low), E2 (Low), Z1 (Low); S3 mitigated (Low).

**Still open:** I1 (Medium, unfixable here), A1 (Medium ops/misconfig — warned), U1 (Low).

**Never done:** invent secrets, decrypt real ZT3 packs, production deploy.

---

## Recommended next (ops / later cycles)

1. On Hetzner: confirm JWT + tokens set, `authSecurityOk=true`, nginx body limit, systemd `ProtectSystem` / `PrivateTmp` active → mark A1/I1 **DEPLOYED** / **END_TO_END_VERIFIED**.
2. Optional: stream upload with early size abort (U1) without full-body buffer.
3. Optional: nsjail/bubblewrap around Ghidra headless (I1) — host change, not small API diff.
