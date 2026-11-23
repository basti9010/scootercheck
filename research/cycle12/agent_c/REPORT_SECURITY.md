# Cycle 12 AGENT C – Deploy Security

**Stand:** 2026-11-23  
**Base:** `origin/cursor/hetzner-deploy-cd-c12-b100`  
**Branch:** `cursor/c12-deploy-security-b100`  
**Scope:** Secrets model, least-privilege SSH, Freigabe, Actions→SSH threat model, auth/diagnostics posture for CD  
**Hard bans honored:** no live SSH · no invented secrets · no host-key check disable · no prod mutate

---

## Executive summary

Cycle 12 CD is **not security-complete** until a human finishes
[`docs/HETZNER_DEPLOYMENT_SETUP.md`](../../../docs/HETZNER_DEPLOYMENT_SETUP.md).
This agent delivered the security contract and docs only — **no** deploy keys, **no**
Environment secrets, **no** workflow enablement from this VM.

Highest residual risks for Actions→SSH:

1. **Stolen GitHub Environment secret** (`DEPLOY_SSH_KEY`) → remote code write + service restart  
2. **Missing environment protection / auto-trigger** → unauthorized prod mutate  
3. **TOFU / `accept-new` / disabled host checks** → MITM on first connect  
4. **Root SSH from CI** → blast radius beyond the app tree  
5. **Live `apiTokenGrantsAdmin=true`** (Cycle 10 LIVE P0) → shared API token = admin; diagnostics must still refuse that path

---

## Deliverables

| File | Role |
|------|------|
| `docs/HETZNER_DEPLOYMENT_SETUP.md` | iPad-friendly setup; Environment `production`; secrets names; keygen; non-root; known_hosts; dispatch+approval; rollback; **setup incomplete until checkboxes done** |
| `docs/DEPLOY_SECURITY.md` | Grants risk; `ADMIN_API_TOKEN`; no shell API; no secrets in logs; rotation; unauthorized-deploy prevention; systemd notes |
| `server/firmware-analysis/docs/process-isolation.md` | Updated: keep existing hardening; optional Cycle 12 directives; auth cross-link |
| This report | Threat model Actions→SSH |

**Scripts:** not modified. Existing `phase1-rollout.sh` already defaults to **dry-run** unless `CONFIRM_PROD_DEPLOY=YES`. CD must preserve that gate and **replace** `root@` + `StrictHostKeyChecking=accept-new` with non-root + pinned `known_hosts` + `yes`.

---

## Threat model: GitHub Actions → SSH → Hetzner

```
[Developer] --workflow_dispatch--> [GitHub Actions runner]
                                         |
                                         | needs: Environment "production" approval
                                         | secrets: DEPLOY_SSH_KEY, DEPLOY_KNOWN_HOSTS, …
                                         v
                                   [ssh deploy@host]
                                         |
                                         | limited sudo: systemctl + release path
                                         v
                          [/opt/scootercheck/firmware-analysis]
                          [systemctl restart scootercheck-fw]
                          [User=scootercheck on 127.0.0.1:8088]
                                         |
                                         v
                              [nginx TLS → public API]
```

### Assets

| Asset | Sensitivity |
|-------|-------------|
| Deploy private key | Critical — host write + restart |
| `/etc/scootercheck/*.env` | Critical — API/admin/JWT/LLM |
| `/var/lib/scootercheck/**` | High — jobs, plaintext, stock |
| App tree `/opt/scootercheck/firmware-analysis` | High — RCE as service user if poisoned |
| GitHub Environment approval | High — human gate |

### Adversaries / paths

| # | Threat | Impact | Mitigation (required) |
|---|--------|--------|------------------------|
| T1 | Compromised GitHub account without Environment review | Prod deploy | Required reviewers on `production` |
| T2 | Repo secret readable by all workflows | Key exfil | Secrets **only** on Environment `production`; branch filter |
| T3 | Workflow logs print PEM / tokens | Key exfil | Never echo secrets; mask; temp `0600` files |
| T4 | MITM / host swap on SSH | Supply-chain on box | Pinned `DEPLOY_KNOWN_HOSTS` + `StrictHostKeyChecking=yes` |
| T5 | CI SSHes as `root` | Full host compromise | Dedicated `DEPLOY_USER`; limited sudoers |
| T6 | Push-triggered prod deploy | Accidental/malicious ship | `workflow_dispatch` only for mutate; confirm input |
| T7 | Dry-run default flipped | Accidental prod write | Default dry-run; `CONFIRM_PROD_DEPLOY` / confirm=YES |
| T8 | CD deletes `/var/lib/scootercheck` | Data loss | Explicit ban in scripts/docs; rsync allow-lists |
| T9 | HTTP “shell” admin API | Remote command exec without SSH | **No shell API**; fixed argv only |
| T10 | Shared token admin | App token → admin | `API_TOKEN_GRANTS_ADMIN=0` + `ADMIN_API_TOKEN`; diagnostics true-admin only |
| T11 | Poisoned release artifact | Code exec as `scootercheck` | Reviewers; server unit tests before restart; rollback bak |
| T12 | Stolen admin token via client logs | Diagnostics / admin abuse | No secrets in logs; rotate checklist |

### Trust boundaries

1. **GitHub → runner:** OIDC/Actions identity; Environment gate is the primary human control.  
2. **Runner → SSH:** Key + known_hosts; treat runner filesystem as hostile after job (delete key files).  
3. **Deploy user → service user:** Deploy may write app files / restart; should **not** read decrypt keys into logs; service drops privileges via systemd.  
4. **Service → network:** Loopback only; nginx is the public edge.  
5. **Admin HTTP → host:** Diagnostics/admin ≠ shell; cannot replace SSH deploy.

### Residual (accepted for Cycle 12 docs phase)

- Agent A workflow YAML may land separately — this report defines the **contract** it must meet.  
- Optional systemd directives not applied live (document-only; need Freigabe + test).  
- Live prod auth posture may still show grants=true until ops sets `ADMIN_API_TOKEN` (Cycle 10 carry-over) — **out of band**, not fixed by this branch.  
- No nsjail/seccomp (I1) — unchanged.

---

## Auth & diagnostics (runtime, not CD)

| Rule | Status in-tree |
|------|----------------|
| `API_TOKEN_GRANTS_ADMIN` default 0 | Yes (`.env.example`, health CRITICAL if 1) |
| Require `ADMIN_API_TOKEN` for secure separated mode | Documented; ops must set on host |
| Diagnostics refuse shared-token admin | `enforce_diagnostics_admin` |
| No shell API / no env dump on diagnostics | Documented + code comments |
| Secrets never in `/health` | Yes (booleans only) |

CD must **not** overwrite host env files from the repo. Rotation is a human checklist in `DEPLOY_SECURITY.md`.

---

## Script / CD gate expectations (for Agent A)

When wiring `deploy-hetzner.yml` (or equivalent):

1. `environment: production`  
2. `workflow_dispatch` inputs: action (`deploy`|`rollback`), `confirm` default empty/`NO`  
3. Abort unless `confirm == YES` for live mutate  
4. Write `known_hosts` from `DEPLOY_KNOWN_HOSTS`; SSH `-o StrictHostKeyChecking=yes`  
5. User = `DEPLOY_USER` (not root)  
6. Never log secret values  
7. Preserve data dirs; prefer release/bak pattern already used by `phase1-rollout.sh`  
8. Post-deploy health on loopback via SSH; rollback on failure  

This Agent C branch does **not** add the workflow (ownership: Agent A / DevOps).

---

## Setup completeness

**SETUP_NOT_COMPLETED** from this agent’s perspective.

Human must still: create Environment + reviewers, generate SSH key once, create non-root deploy user, capture known_hosts, paste Environment secrets, approve first dry dispatch.

Grades: **DOCUMENTED** ≠ **CONFIGURED** ≠ **DEPLOYED** ≠ **VERIFIED**.

---

## Out of scope / not done here

- Live SSH or host verification  
- Inventing or rotating real tokens  
- Changing prod `API_TOKEN_GRANTS_ADMIN`  
- Adding/weakening systemd on the VPS  
- Implementing `deploy-hetzner.yml`  

---

## References

- Kickoff: `research/cycle12/CYCLE12_KICKOFF.md`  
- Cycle 10 security: `research/cycle10/agent_c/REPORT_SECURITY_FORENSIC_QA.md`  
- Rollback: `server/firmware-analysis/docs/phase22h-rollback-plan.md`  
- Unit: `server/firmware-analysis/deploy/scootercheck-fw.service`  
