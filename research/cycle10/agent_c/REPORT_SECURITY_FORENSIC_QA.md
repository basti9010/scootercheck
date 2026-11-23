# Cycle 10 AGENT C – Security & Forensic QA

**Stand:** 2026-11-23  
**Base:** `cursor/hetzner-ghidra-live-c10-b100`  
**Branch:** `cursor/security-forensic-qa-c10-b100`  
**Scope:** P0 auth/admin rights clarity; path confinement re-check (C9); process isolation docs; temp files; Ghidra reproducibility  
**Host:** Cloud Agent VM — **NOT DEPLOYED**; no SSH / no admin API token / no secrets invented.

---

## Executive summary

Public prod `/health` still shows the Cycle 8/9 P0 posture: **`apiTokenGrantsAdmin=true`**, **`adminApiTokenConfigured=false`**, and **missing** `authSecurityOk` / `authMode` fields (deploy lags in-tree Phase 2.2H.2+). In-tree defaults already keep grants off; this cycle elevates shared-token-admin to **CRITICAL**, clarifies `authSecurityOk` (CRITICAL/INSECURE only), and documents process isolation + Ghidra reproducibility. Path confinement (C9) remains green.

| # | Item | Status | Notes |
|---|------|--------|-------|
| P0 | Fail-closed auth / open-auth | **PASS + CRITICAL-warned** | `auth=open` → `authMode=open`, `authSecurityCritical=true` |
| P0 | User vs admin separation | **PASS in-tree** | Default `API_TOKEN_GRANTS_ADMIN=0`; shared token ≠ admin |
| P0 | `apiTokenGrantsAdmin` prod risk | **LIVE P0 (ops)** | Prod grants=true + no admin token; in-tree now CRITICAL-flags that posture |
| — | Health flag clarity | **FIXED** | `authMode`, `authSecurityOk`, `authSecurityCritical` |
| C9 | Path confinement | **PASS** | Regression suite green |
| I1 | Process isolation | **DOCUMENTED / untestable** | systemd unit checklist; no host proof |
| — | Temp files | **PASS** | `_secure_mkdir` 0o750; PrivateTmp documented |
| — | Ghidra reproducibility | **PASS (unit)** | `ghidra_reproducibility` suite; live headless **NOT_TESTED** |

---

## Live public `/health` (read-only, 2026-11-23)

`GET https://api.tuningscanner.de/scootercheck-fw/health` → HTTP 200

| Flag | Live value | In-tree secure target |
|------|------------|------------------------|
| `jwtConfigured` | true | true |
| `apiTokenConfigured` | true | true |
| `adminApiTokenConfigured` | **false** | **true** |
| `apiTokenGrantsAdmin` | **true** | **false** |
| `authMode` / `authSecurityOk` / `authSecurityCritical` | **absent** | `separated` / true / false |

**Evidence class:** LIVE (public). No settings changed. No secrets observed in response.

After next deploy of this tree + env fix (`ADMIN_API_TOKEN` set, `API_TOKEN_GRANTS_ADMIN=0`), the same probe should report `authMode=separated`, `authSecurityOk=true`. Until then, treat live admin ACL as **shared-token admin**.

---

## Code changes (this branch)

### 1. Health auth posture clarity — `app.py`

- `authMode`: `open` | `shared_token_admin` | `separated`
- `authSecurityCritical`: any `CRITICAL:` warning
- `authSecurityOk`: **false** only for `CRITICAL:` / `INSECURE:` (ADVISORY no longer fails the gate)
- Shared-token admin (`API_TOKEN_GRANTS_ADMIN=1`) elevated **INSECURE → CRITICAL**
- Prod-like “shared token is only admin credential” elevated **CRITICAL**
- Open-auth remains **CRITICAL** with `auth=open`
- Soft JWT / missing-admin (when grants=0) → **ADVISORY**

### 2. Defaults / docs / comments

- `job_auth.py`: discourage shared-token admin in module contract
- `.env.example`, `README.md`, `docs/phase22h2-release.md`: must-keep-0 language; health field contract
- **New** `docs/process-isolation.md`: systemd hardening + temp dirs + Ghidra reproducibility checklist

### 3. Tests

- `test_api_auth_security.py`: open-auth CRITICAL; grants-admin CRITICAL (prod-like); JWT ADVISORY does not fail `authSecurityOk`; `authMode=separated` happy path
- `test_path_confinement.py`, `test_phase22h2_jwt_e2e.py`, `test_cycle9_server_validation.py`: assert new flags

---

## Pytest (this review)

```
88 passed, 4 skipped  (auth + path + job ACL + JWT e2e + phase22g reproducibility + cycle9 validation)
43 passed             (re-check: cycle9 + api_auth + path_confinement after flag asserts)
```

Primary suites: `test_api_auth_security.py`, `test_path_confinement.py`, `test_job_auth.py`, `test_phase22h2_jwt_e2e.py`, `test_phase22g.py`, `test_cycle9_server_validation.py`.

---

## Path confinement (C9 re-check)

| Check | Result |
|-------|--------|
| Store-root confinement (plaintext/decompile) | PASS |
| Symlink escape → opaque 404 | PASS |
| ZIP `\` traversal rejected | PASS (prior) |
| Job ACL before artifact FileResponse | PASS |
| Absolute path disclosure (basename only) | PASS |

No new confinement bugs found; no prod deploy of confinement code verified from this VM.

---

## Process isolation / temp / Ghidra reproducibility

| Topic | Finding |
|-------|---------|
| systemd | Unit ships `PrivateTmp`, `ProtectSystem=strict`, `NoNewPrivileges`, localhost bind — **host active state UNKNOWN** |
| Analyzer sandbox | Ghidra/r2/unicorn/angr share service UID — residual **I1 Medium** |
| Temp | Job dirs `0o750`; prod should use `/var/lib/scootercheck/…` not world `/tmp` |
| Reproducibility | Normalized semantic hashes ignore timestamps/order; unit tests PASS; live dual-run **NOT_TESTED** (no `GHIDRA_HOME`) |

---

## Residual risks

| Sev | ID | Item | Why open |
|-----|-----|------|----------|
| **P0 / Medium** | **A-PROD** | Live `apiTokenGrantsAdmin=true` + no `ADMIN_API_TOKEN` | Ops must set env + deploy tree with health fields; **not done here** |
| Medium | **I1** | Analyzer process isolation | No nsjail/seccomp; untestable without host |
| Medium | **A1** | Open-auth code path | Still allowed for local/dev when all secrets unset; CRITICAL-warned; must not public-bind |
| Low | **U1** | Upload full-body buffer | nginx body limit remains edge mitigator |
| Info | **DEPLOY-LAG** | Prod missing `authSecurityOk` fields | Confirms live revision ≠ current tree |

---

## What was never done

- Invent / store secrets  
- Change production env or restart services  
- TEA decrypt / live Ghidra on Hetzner  
- Claim END_TO_END_VERIFIED for prod auth

---

## Recommended next (ops)

1. On Hetzner: set `ADMIN_API_TOKEN`, `API_TOKEN_GRANTS_ADMIN=0`, `TRUST_API_TOKEN_CLIENT_ID=0`; restart worker; confirm `authMode=separated`, `authSecurityOk=true`, `authSecurityCritical=false`.
2. Confirm systemd hardening via `docs/process-isolation.md` checklist → mark I1 host-verified or escalate to nsjail.
3. Dual Ghidra run on same plaintext → `ghidra_reproducibility.compare_runs` → `reproducible=true`.

---

## Files changed

| File | Change |
|------|--------|
| `server/firmware-analysis/app.py` | authMode / CRITICAL grants / authSecurityOk gate / authSecurityCritical |
| `server/firmware-analysis/job_auth.py` | Docs: discourage shared-token admin |
| `server/firmware-analysis/test_api_auth_security.py` | Open-auth + grants-admin + ADVISORY tests |
| `server/firmware-analysis/test_path_confinement.py` | CRITICAL open-auth assert |
| `server/firmware-analysis/test_phase22h2_jwt_e2e.py` | New health flags |
| `server/firmware-analysis/test_cycle9_server_validation.py` | New health flags |
| `server/firmware-analysis/.env.example` | Stronger grants=0 guidance |
| `server/firmware-analysis/README.md` | Auth / health / isolation pointers |
| `server/firmware-analysis/docs/phase22h2-release.md` | Health contract |
| `server/firmware-analysis/docs/process-isolation.md` | **New** |
| `research/cycle10/agent_c/REPORT_SECURITY_FORENSIC_QA.md` | This report |
