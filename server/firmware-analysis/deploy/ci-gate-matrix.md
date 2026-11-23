# Cycle 12 — CI gate matrix (server deploy)

**Stand:** 2026-11-23  
**Owner:** Agent D (QA)  
**Workflow:** `.github/workflows/server-firmware-tests.yml`

Epistemic: **DEPLOYED ≠ AVAILABLE ≠ TESTED ≠ END_TO_END_VERIFIED**.  
A green server pytest job means **TESTED** (subset, offline). It does **not** mean live Hetzner deploy or E2E decrypt/Ghidra without Freigabe.

## Required for server deploy merge / docs

| Gate | Path / job | Why mandatory |
|------|------------|---------------|
| Server pytest subset | `server-firmware-tests.yml` → `pytest-subset` | Auth, path confinement, ZIP safety, diagnostics honesty, deploy-smoke logic |
| Auth security | `test_api_auth_security.py` | Open-auth / ownership regressions block release |
| Path confinement | `test_path_confinement.py` | Store-root escape must fail CI (PR #108 lineage) |
| ZIP safety | `test_zip_safe.py` | Upload traversal / zip-bomb guards |
| Diagnostics (if present) | `test_diagnostics_*.py` | CONFIGURED ≠ VERIFIED; admin gate (PR #110) |
| Deploy smoke logic | `test_deploy_smoke_logic.py` + `deploy_smoke_logic.py` | Health parse + rollback triggers **without** SSH |
| Deploy manifest | `test_deploy_manifest.py` | CD file list + release-config validation (offline) |

Mark **`Server Firmware Tests` / `server-firmware-tests`** as a **required** status check for PRs that change `server/firmware-analysis/**` or deploy docs that claim a server release.

## Optional for server deploy (do not block server-only merges)

| Gate | Path / job | Notes |
|------|------------|-------|
| iOS XCTest | `ios-unit-tests.yml` | macOS simulator; valuable for app, **not** required to ship server FastAPI |
| TestFlight | `testflight.yml` | Signing / distribution — unrelated to Hetzner fw service |
| Heavy forensics | `test_unicorn_angr.py`, angr, live Ghidra | Optional / skipped without host tools |
| Live Hetzner smoke | SSH + curl prod `/health` | **Freigabe only**; Cloud VM has no deploy key (Cycle 10) |
| Real TEA decrypt | ninebottea + real packs | Hard ban in CI; fixtures/probes only |

### PR #110 note

PR #110 included a Swift compile fix (`analysisLimitations` argument order). That is an **iOS** fix. Server deploy gating must not wait on green iOS XCTest solely because of that change. Server and iOS gates are independent.

## Rollback / smoke policy

| Condition | Expected |
|-----------|----------|
| `CONFIRM_PROD_DEPLOY≠YES` / dry-run | No remote writes, no rollback side effects |
| Restart fails / health curl fails / `ok≠true` | Rollback to backup (see `deploy/phase1-rollout.sh`) |
| `/health` flags only | At most **CONFIGURED** — never claim **VERIFIED** |
| Post-deploy smoke | `deploy/post-deploy-smoke.sh` env: `HEALTH_URL`, `REMOTE_SMOKE`, `PUBLIC_SMOKE`, `SMOKE_ADMIN_TOKEN` — live curl/SSH needs Freigabe |
| Offline smoke helpers | Prefer `--health-json` / `parse_post_deploy_smoke_env` in CI; `--live` needs Freigabe |

Interface helpers: `deploy_smoke_logic.py` (`parse_smoke_argv`, `parse_post_deploy_smoke_env`, `evaluate_rollback`, `assert_no_verified_from_configured_only`).

## What this matrix does **not** claim

- No production deploy from GitHub Actions root.
- No END_TO_END_VERIFIED without authenticated Freigabe smoke.
- No fake-green: workflow fails when pytest fails; skipped heavy suites are not reported as passed probes.
