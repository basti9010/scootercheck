# Cycle 8 AGENT D – QA & Security Review

**Stand:** 2026-11-23  
**Base:** `cursor/server-deploy-ghidra-ios-c8-b100`  
**Review branch:** `cursor/qa-security-cycle8-c579`  
**Scope:** `server/firmware-analysis` (code + existing tests; authorized synthetic fixtures only)  
**Host:** Cloud Agent VM — **NOT DEPLOYED**; Hetzner unreachable; App secrets empty; no ninebottea / decrypt keys / Ghidra on this host.

**Epistemic note:** Grades below are from static review + local pytest. Live TLS, production systemd confinement, and decrypt-path E2E are **NOT_TESTED** here.

---

## Executive summary

| # | Item | Verdict | Highest severity finding |
|---|------|---------|---------------------------|
| 1 | Upload security | **PASS** | Low — full-body buffer before size check (nginx mitigates) |
| 2 | File size limits | **PASS** | — |
| 3 | Safe ZIP / path traversal | **PASS** | Low — Windows-backslash `..` names not rejected (dest path fixed) |
| 4 | Auth (token/JWT) | **PASS** | Medium — open-auth if all secrets unset |
| 5 | API error handling | **PASS** | Low — JWT decode exception text in 401 detail |
| 6 | Secure storage of jobs | **PASS** (with residuals) | Medium — absolute paths in API; plaintext download not path-confined |
| 7 | Secret handling | **PASS** | Low — `.gitignore` previously omitted `.env` (fixed this review) |
| 8 | Analysis isolation | **PASS** (design) / **INCOMPLETE** (host) | Medium — Ghidra/r2/unicorn not process-sandboxed beyond systemd |
| 9 | Reproducibility | **PASS** | — (helpers + tests; live dual-run **NOT_TESTED**) |
| 10 | Firmware integrity (SHA-256) | **PASS** | Low — client meta SHA not compared for mismatch warning |

**Overall:** Core upload/ZIP/auth/ownership controls are solid and well-tested. Residual risks are defense-in-depth and ops/misconfiguration, not missing primary gates. Decrypt of real ZT3 packs and production deploy verification remain **INCOMPLETE** by design (no keys / no host).

---

## Pytest results (this review)

Light deps only (`fastapi`, `uvicorn`, `pydantic`, `PyJWT`, `httpx`, `python-multipart`). **No** angr / yara / unicorn / capstone / Ghidra / ninebottea installed.

```
113 passed, 6 skipped
```

Suites run:

- `test_zip_safe.py`
- `test_job_auth.py`
- `test_api_auth_security.py`
- `test_phase22h1_validation.py`
- `test_phase22h2_jwt_e2e.py`
- `test_phase22h_e2e.py` (Ghidra paths skipped)
- `test_plaintext_detect.py`
- `test_phase22g.py` (reproducibility helpers)
- `test_reference_catalog.py` (SHA mismatch rejection)
- `test_upload_integrity_sha256.py` (**new** — server SHA wins over client meta lie; 80 MiB limit; oversized reject)

Skipped cases: heavy/Ghidra-dependent paths only.

---

## Item findings

### 1. Upload security — **PASS**

**Evidence**

- `POST /v1/firmware/jobs` requires `require_auth`.
- Upload filename sanitized (`/` → `_`); archive stored under `job_dir/upload/`.
- ZIP uploads call `inspect_zip` before persist; bare `.bin`/`.enc` use size check only.
- `allowDecrypt=false` fails closed in worker.

**Findings**

| Sev | ID | Note |
|-----|-----|------|
| Low | U1 | `await archive.read()` buffers entire body before `validate_upload_size`. Without reverse-proxy body limit, memory DoS possible. Mitigated by `deploy/nginx-fw.conf.example` `client_max_body_size 80m`. |
| Info | U2 | No Content-Type allowlist (by design for firmware blobs). |

### 2. File size limits — **PASS**

**Evidence**

| Limit | Default | Env |
|-------|---------|-----|
| Upload | 80 MiB | `FW_MAX_UPLOAD_BYTES` |
| Uncompressed ZIP total | 256 MiB | `FW_MAX_UNCOMPRESSED_BYTES` |
| Per member | 64 MiB | `FW_MAX_SINGLE_MEMBER_BYTES` |
| Extract memory budget | 96 MiB | `FW_MAX_EXTRACT_MEMORY_BYTES` |
| Entry count | 256 | `FW_MAX_ZIP_ENTRIES` |
| Compression ratio | 80× | `FW_MAX_COMPRESSION_RATIO` |
| Stock admin upload | 16 MiB | hardcoded |
| info.json | 2 MiB | hardcoded |

Nginx example aligns at 80 m. Covered by `test_zip_safe` + new integrity tests.

### 3. Safe ZIP extraction / path traversal — **PASS**

**Evidence** (`zip_safe.py`)

- Rejects empty names, null bytes, absolute paths, `..` path parts, Unix symlinks (`S_IFLNK`).
- Zip-bomb checks on declared sizes; `safe_extract_member` enforces **runtime** byte limits and deletes partial files.
- Extract destination for payloads is **caller-controlled** (`FIRM.bin.enc`), not member name → traversal on member name cannot escape job dir for the main pipeline.

**Findings**

| Sev | ID | Note |
|-----|-----|------|
| Low | Z1 | On Linux, member names like `..\\..\\evil` are not split by `Path.parts`; not rejected. Current extract paths ignore member name for dest → not exploitable today. |
| Info | Z2 | Declared ZIP sizes can lie; runtime extract cap closes the bomb path for selected members. |

Tests: path traversal, absolute, symlink, entry flood, ratio bomb, empty upload — **PASS**.

### 4. Auth (token/JWT) — **PASS**

**Evidence** (`job_auth.py`, `app.require_auth`)

- Bearer JWT preferred over shared token; `status=active` required; missing `sub` → 401.
- Secure defaults: `API_TOKEN_GRANTS_ADMIN=0`, `TRUST_API_TOKEN_CLIENT_ID=0`.
- Unauthorized job access → opaque **404** (no existence leak).
- Admin via JWT `role=admin` or `ADMIN_API_TOKEN`.
- Health exposes `authSecurityOk` / warnings for insecure legacy flags.

**Findings**

| Sev | ID | Note |
|-----|-----|------|
| Medium | A1 | If `API_TOKEN`, `ADMIN_API_TOKEN`, and `JWT_SECRET` are all unset → `auth=open` (dev mode). Documented; catastrophic if mis-deployed without nginx+secrets. |
| Low | A2 | Shared `API_TOKEN` still authenticates any holder; ownership unbound unless JWT (by design). Prefer JWT for multi-user. |

Extensive unit + HTTP + Phase 2.2H.2 JWT E2E coverage — **PASS**.

### 5. API error handling — **PASS**

**Evidence**

- Validation / ZIP failures → 400 with German user-facing `ZipSafetyError` text.
- Auth failures → 401/403; job ACL → 404.
- Decrypt/worker failures → job `state=failed` + `errorCode` (no uncaught crash for expected paths).
- Artifact JSON endpoints use `_job_artifact_path` confinement.

**Findings**

| Sev | ID | Note |
|-----|-----|------|
| Low | E1 | `invalid token: {e}` embeds PyJWT exception string (algorithm/claim hints). Prefer generic `invalid token`. |
| Low | E2 | Decompile preview JSON returns absolute server `path` (FS layout leak to authorized owner). |
| Info | E3 | No global exception handler customizing 500 bodies; FastAPI default may include detail in debug — ensure production `debug=False` (uvicorn default). |

### 6. Secure storage of jobs — **PASS** (residuals)

**Evidence**

- Layout: `WORK_DIR/YYYY/MM/DD/<uuid>/` + `status.json`.
- Retention `JOB_RETENTION_DAYS=30`, soft cap `MAX_STORED_JOBS=500`, cleanup on submit/admin.
- systemd unit: `User=scootercheck`, `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`, bind-scoped `ReadWritePaths`.
- Ownership fields persisted on create.

**Findings**

| Sev | ID | Note |
|-----|-----|------|
| Medium | S1 | `job_status_payload` returns absolute `plaintextPath` / `decompilePath` to clients. |
| Medium | S2 | `download_plaintext` / `download_decompile` / promote path use raw `Path(job["plaintextPath"])` **without** store-root confinement (unlike `_job_artifact_path` for functions/callgraph). Exploit requires poisoned `status.json` (local FS write) + auth as owner — defense-in-depth gap. |
| Low | S3 | Job dirs created with default umask; no explicit `0o750`/`chmod`. Acceptable under dedicated service user. |

### 7. Secret handling — **PASS**

**Evidence**

- Repo ships `.env.example` placeholders only (`change-me`).
- `decrypt-firm.example.sh` sources `/etc/scootercheck/decrypt.env` (host-only); README states no ninebottea/keys in repo.
- No tracked `.env`, `decrypt.env`, PEM, or real API keys (`git ls-files` clean).
- LLM tests use fake `sk-…` fixtures; reject OAuth-style tokens.
- TestFlight `.p8` via GitHub Secrets; `*.p8` gitignored.

**Findings**

| Sev | ID | Note |
|-----|-----|------|
| Low | K1 | Root `.gitignore` previously lacked `.env` / `decrypt.env` patterns → accidental commit risk. **Fixed** on this branch. |
| Info | K2 | `install-on-hetzner.sh` copies `JWT_SECRET` from auth `.env` on host — ops-only; not a repo secret. |

**Never invent keys / never decrypt real ZT3 packs** — followed. Live decrypt capability here: **INCOMPLETE**.

### 8. Analysis isolation — **PASS** (code) / **INCOMPLETE** (host proof)

**Evidence**

- angr: dedicated subprocess + `RLIMIT_AS` + wall timeout + optional nice; symbolic off by default; serialized with Ghidra via `_HEAVY_ANALYSIS_LOCK`.
- Ghidra / r2 / decrypt: `subprocess.run` with timeouts; decrypt argv is fixed wrapper + paths (no shell).
- Unicorn: instruction count + timeout caps in emulate helpers.
- Staging harness isolates WORK_DIR for tests (no `/var/lib/scootercheck`).

**Findings**

| Sev | ID | Note |
|-----|-----|------|
| Medium | I1 | Ghidra Headless / r2 / unicorn share the service UID; no seccomp/nsjail. Malicious firmware could stress CPU/RAM or exploit analyzer bugs → host process compromise risk. systemd hardening helps but is **NOT_TESTED** from this VM. |
| Info | I2 | `ENABLE_ANGR` defaults on when package present; keep mem/timeout caps. |

### 9. Reproducibility — **PASS**

**Evidence**

- `ghidra_reproducibility.py`: canonical normalize + `semantic_hash`; `compare_runs` strips volatile fields.
- `analysis_profile` separates soft runtime fields (timeout/heap/version) from semantic profile hash.
- Tests in `test_phase22g.py` cover hash stability and diff detection.

Live dual Ghidra runs on identical firmware: **NOT_TESTED** here (no Ghidra).

### 10. Firmware integrity (SHA-256) — **PASS**

**Evidence**

- Server computes `archiveSHA256` via `sha256_bytes(raw)` at upload; worker also hashes enc + plaintext.
- Catalog loader rejects meta/firmware SHA mismatch (`test_reference_catalog.test_sha_mismatch_rejected`).
- New test: client `meta.archiveSHA256` lie is **ignored**; job stores true digest.

**Findings**

| Sev | ID | Note |
|-----|-----|------|
| Low | H1 | No explicit mismatch warning when client meta SHA ≠ server digest (client field effectively unused for integrity). Harmless if clients ignore returned SHA; prefer optional `archiveSHA256ClientMismatch` note. |

---

## Changes on this branch (safe only)

1. `research/cycle8/agent_d/REPORT_QA_SECURITY.md` — this report.
2. `server/firmware-analysis/test_upload_integrity_sha256.py` — SHA / size regression tests (synthetic).
3. `.gitignore` — ignore `.env`, `.env.*` (keep `.env.example`), `**/decrypt.env`, `server/firmware-analysis/.env`.

No production deploy, no secrets, no decrypt of real packs.

---

## Top 5 residual risks

1. **Open-auth misdeploy (A1)** — empty secrets → `auth=open`; any unauthenticated client can submit/read if the port is exposed.
2. **Analyzer process isolation (I1)** — Ghidra/r2/unicorn under service UID; firmware-triggered tool bugs are not contained beyond systemd.
3. **Plaintext/decompile path confinement (S2)** — download/promote trust `status.json` paths without store-root checks.
4. **Absolute path disclosure (S1/E2)** — owners see server filesystem paths in job/decompile responses.
5. **Upload memory DoS without proxy (U1)** — rely on nginx `client_max_body_size`; bare uvicorn on a public bind is unsafe.

---

## Recommended follow-ups (not done here)

1. Constrain `plaintextPath` / `decompilePath` to `PLAINTEXT_STORE` / `DECOMPILE_STORE` / job dir before `FileResponse`.
2. Strip absolute paths from client-facing job payloads (keep SHA + flags).
3. Generic JWT 401 detail (no exception string).
4. Reject ZIP member names containing `\\` or normalize separators before `..` checks.
5. Ops: confirm production env has JWT + tokens set, `authSecurityOk=true`, nginx body limit, systemd unit active — **END_TO_END_VERIFIED** only after host access.

---

## Verdict matrix (quick)

| Item | PASS/FAIL/INCOMPLETE |
|------|----------------------|
| 1 Upload security | PASS |
| 2 File size limits | PASS |
| 3 Safe ZIP / path traversal | PASS |
| 4 Auth (token/JWT) | PASS |
| 5 API error handling | PASS |
| 6 Secure job storage | PASS |
| 7 Secret handling | PASS |
| 8 Analysis isolation | PASS (code) / INCOMPLETE (host) |
| 9 Reproducibility | PASS |
| 10 Firmware integrity SHA-256 | PASS |
