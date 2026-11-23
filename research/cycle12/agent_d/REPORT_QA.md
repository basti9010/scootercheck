# Cycle 12 AGENT D – QA / CI gate

**Stand:** 2026-11-23  
**Base:** `origin/cursor/hetzner-deploy-cd-c12-b100`  
**Branch:** `cursor/c12-deploy-qa-b100`

## Goal

Make server deploy merge criteria honest and testable offline: mandatory Python pytest subset, smoke/rollback decision logic without SSH, CI gate matrix that separates server vs optional iOS.

## Deliverables

| Path | Role |
|------|------|
| `.github/workflows/server-firmware-tests.yml` | PR/push on `server/firmware-analysis/**` (+ deploy workflow) → Python 3.12 + requirements + pytest subset |
| `server/firmware-analysis/deploy_smoke_logic.py` | Pure helpers: health parse, grade honesty, rollback, CLI/env parse |
| `server/firmware-analysis/test_deploy_smoke_logic.py` | Unit tests — **no network / no SSH** |
| `server/firmware-analysis/deploy/ci-gate-matrix.md` | Mandatory vs optional gates |
| `research/cycle12/agent_d/REPORT_QA.md` | This report |

## Mandatory pytest subset (deploy gate)

- `test_api_auth_security.py`
- `test_path_confinement.py`
- `test_zip_safe.py`
- `test_diagnostics_routes.py` / `test_diagnostics_tea.py` / `test_diagnostics_ghidra.py`
- `test_deploy_smoke_logic.py`
- `test_deploy_manifest.py`

## Optional (not required for server deploy)

- iOS XCTest (`.github/workflows/ios-unit-tests.yml`) — including PR #110 Swift `analysisLimitations` order fix
- TestFlight workflow
- Live Hetzner post-deploy smoke / real TEA decrypt / headless Ghidra E2E

## Epistemic honesty (CI status)

| Claim | Grade on this agent |
|-------|---------------------|
| Offline unit / logic tests | **TESTED** — `111 passed` on mandatory subset (local Python 3.12) |
| GitHub Actions green on this branch | **NOT_TESTED** until push + Actions run; workflow is defined to fail on pytest failure (no fake-green) |
| Hetzner deploy / systemd / nginx | **NOT_TESTED** — no deploy key; hard ban on prod deploy |
| Live `/health` / diagnostics selftest | **NOT_TESTED** — needs Freigabe + secrets |
| TEA/Ghidra **VERIFIED** from `/health` flags | **REFUSED** by design (`CONFIGURED ≠ VERIFIED`) |
| **END_TO_END_VERIFIED** | **NOT claimed** — no Freigabe E2E |

## Smoke / rollback coverage (offline)

- Parse `/health` JSON; reject missing/`ok` type errors
- `decryptConfigured` / `ghidraConfigured` → at most **CONFIGURED**
- Fail if **VERIFIED** / **END_TO_END_VERIFIED** claimed from flags alone
- Fail smoke when `authMode=open`
- Rollback triggers: restart fail, health curl fail, `ok≠true`, import/tests fail; dry-run never rolls back
- Env contract for `deploy/post-deploy-smoke.sh` (`HEALTH_URL`, `REMOTE_SMOKE`, `PUBLIC_SMOKE`, `SMOKE_ADMIN_TOKEN`) parsed in Python without executing curl/SSH

## Hard bans respected

- No production deploy from this agent  
- No real firmware decrypt  
- No invented green CI / no E2E claim without Freigabe  

## Residual

1. Branch protection must mark **Server Firmware Tests** required (ops step — not done from this VM).  
2. Live smoke after first Freigabe deploy remains Agent A + ops.  
3. Parallel Cycle 12 agents may still extend release scripts; QA gate stays fixture-based.
