# Deployment Status

**Inventory date:** 2026-11-28  
**Prod deploy from this automation effort:** **not performed** (and must not be).

## Firmware-analysis → Hetzner

| Item | Status |
|------|--------|
| CD workflow | IMPLEMENTED — `.github/workflows/deploy-hetzner.yml` |
| Trigger | `workflow_dispatch` only (no push auto-prod) |
| Gates | Full 40-char SHA; Server Firmware Tests success; `confirm_deploy`; Environment `production` approval |
| Host key policy | `StrictHostKeyChecking=yes` + `HETZNER_SSH_KNOWN_HOSTS` |
| Rollback | Smoke fail → workflow rollback; manual `release-rollback.sh` + `CONFIRM_PROD_DEPLOY=YES` |
| Setup checklist | **Open** — see `docs/HETZNER_DEPLOYMENT_SETUP.md` |
| DEPLOYED via CD | **No** / NOT VERIFIED |
| END_TO_END_VERIFIED | **No** |

### Host paths (docs)

- App symlink: `/opt/scootercheck/firmware-analysis` → `releases/<sha>`
- Data: `/var/lib/scootercheck/*` (untouched by rollback)
- Env: `/etc/scootercheck/firmware-analysis.env`, `decrypt.env`

### Auth posture target (ops)

`apiTokenGrantsAdmin=false`, dedicated `ADMIN_API_TOKEN`, diagnostics admin-only — **live flags not probed by this agent**.

## TestFlight / iOS

| Item | Status |
|------|--------|
| Workflow | `.github/workflows/testflight.yml` + `docs/TESTFLIGHT.md` / Codemagic |
| Bundle | `com.scootercheck.app` |
| PR #117 note | TestFlight build/upload claimed SUCCESS (#346) on that line — verify there |
| PR #114 | Demo bypass TF branch — **do not promote as lasting release** |

## What agents must not do

- Do not set `confirm_deploy=true` or approve production Environment.
- Do not SSH to prod or rotate live secrets from chat.
- Do not claim DEPLOYED without host smoke evidence.
