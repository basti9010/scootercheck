# Cycle 12 AGENT A – DevOps / Hetzner CD

**Date:** 2026-11-23  
**Branch:** `cursor/c12-devops-deploy-b100`  
**Base:** `origin/cursor/hetzner-deploy-cd-c12-b100`  
**Hard bans observed:** no prod deploy · no invented credentials · no `StrictHostKeyChecking=no` · no root as Actions default · no second architecture  

Evidence class: **LIVE** = probed this Cloud VM / public URL this run · **REPO** = derived from git files only.

---

## Access verdict

| Capability | Result |
|------------|--------|
| SSH / systemd / `/etc/scootercheck` | **Blocked** — `~/.ssh` absent on this Cloud VM |
| Live `CONFIRM_PROD_DEPLOY=YES` | **Not performed** (hard ban) |
| Public `GET …/scootercheck-fw/health` | **LIVE** reachable |
| GitHub Environment secrets / reviewers | **Not configurable from here** — documented only |

---

## Deliverables (REPO)

| Artifact | Role |
|----------|------|
| `.github/workflows/deploy-hetzner.yml` | `workflow_dispatch` only; `environment: production`; concurrency `deploy-hetzner-production` (`cancel-in-progress: false`) |
| `.github/workflows/server-firmware-tests.yml` | Server CI gate target (iOS non-blocking) |
| `deploy/release-deploy.sh` | Versioned `/opt/scootercheck/releases/<sha>/` + symlink flip + flock + health |
| `deploy/release-rollback.sh` | Point symlink to previous/explicit SHA, restart, health |
| `deploy/post-deploy-smoke.sh` | systemd + health + auth flags; TEA/Ghidra CONFIGURED≠VERIFIED; E2E=NO |
| `deploy/bootstrap-deploy-user.sh` | ONE-TIME least-privilege user; **default dry-run** |
| `docs/HETZNER_DEPLOYMENT_SETUP.md` | iPad-friendly ops checklist |
| `deploy/scootercheck-fw.service` | `ReadWritePaths` includes `/opt/scootercheck/releases` for symlink layout |

Layout preserved: app symlink `/opt/scootercheck/firmware-analysis`, data `/var/lib/scootercheck`, secrets `/etc/scootercheck/*.env`.

---

## Workflow gates (summary)

1. **Input:** full **40-char** `git_sha` (branch tips refused) + `confirm_deploy` (default false).  
2. **validate:** resolve commit object; require successful **Server Firmware Tests** for that SHA when `server-firmware-tests.yml` exists (fail-closed if no run); `skip_ci_gate` emergency only.  
3. **iOS XCTest:** explicitly **non-blocking** for server deploy.  
4. **dry_run:** local summary, or optional `remote_dry_run` SSH plan under `environment: production` (no writes).  
5. **deploy:** only if `confirm_deploy=true` + Environment approval; secrets `HETZNER_SSH_*`, optional `HETZNER_DEPLOY_PATH`, `HEALTH_URL`, `SMOKE_ADMIN_TOKEN`.  
6. **SSH:** `StrictHostKeyChecking=yes` + `UserKnownHostsFile` from secret — never `accept-new` / `false`.  
7. **smoke → rollback:** on smoke failure after successful release, auto `release-rollback.sh`.  
8. **Mutex:** remote `flock` on `/var/lock/scootercheck-fw-deploy.lock`.  
9. **User:** prefer `scootercheck-deploy` (warn if `HETZNER_SSH_USER=root`).  
10. **Environment reviewers:** must be set in GitHub UI — cannot configure via API from Cloud Agents.

---

## Honest grades

| Surface | DEPLOYED | AVAILABLE | TESTED | END_TO_END_VERIFIED |
|---------|----------|-----------|--------|---------------------|
| CD workflow + scripts in git | **YES** (REPO) | N/A | **YES** unit (`test_deploy_*`, `bash -n`) | **NO** |
| GitHub Actions live run | **NO** | **NO** | **NO** | **NO** |
| Hetzner release symlink layout | **NO** (not applied) | **NO** | **NO** | **NO** |
| `scootercheck-deploy` user | **NO** (script dry-run only) | **NO** | DRY-RUN script only | **NO** |
| Public health endpoint | N/A | **YES** (LIVE `ok:true`) | read-only curl | **NO** |
| TEA (`decryptConfigured`) | N/A | flag **CONFIGURED** (LIVE) | **≠ VERIFIED** | **NO** |
| Ghidra (`ghidraConfigured`) | N/A | flag **CONFIGURED** (LIVE) | **≠ VERIFIED** | **NO** |
| Prod deploy this run | **NO** | — | — | **NO** (no Freigabe / no SSH key) |

### LIVE health snapshot (flags only, 2026-11-23)

- `ok=true`, `jwtConfigured=true`, `decryptConfigured=true`, `ghidraConfigured=true`  
- `apiTokenGrantsAdmin=true`, `adminApiTokenConfigured=false` → security follow-up (Agent C / ops); **not** claimed fixed by this agent  
- CONFIGURED health flags are **not** execution proof for TEA/Ghidra jobs  

### E2E

**E2E = NO** without human Freigabe, Environment secrets, deploy-user bootstrap, and real (or approved fixture) firmware jobs. This agent did not and must not perform production deploy from the Cloud VM.

---

## Ops remaining (human)

See `docs/HETZNER_DEPLOYMENT_SETUP.md` checklist: Environment `production` + reviewers, SSH secrets, `bootstrap-deploy-user.sh` live once, harden `API_TOKEN_GRANTS_ADMIN=0`, then dry-run Actions, then deliberate `confirm_deploy=true`.
