# Cycle 12 Kickoff – Automated Hetzner Deployment & CD

**Base tip:** `cursor/server-diagnostics-c11-b100` (+ Swift arg-order fix)  
**Working branch:** `cursor/hetzner-deploy-cd-c12-b100`  
**Hard bans:** no prod deploy · no secret invent · no root GitHub Actions · no disabled host-key check · no second architecture

## Phase 1 inventory (PM)

| PR | Theme | Role for deploy |
|----|-------|-----------------|
| #103 | Multi-Agent System | Process docs |
| #104 | Firmware Research Lab | Research only |
| #105 | Server Firmware Analysis | Core FastAPI |
| #106 | Ghidra & iOS | Ghidra scripts + iOS |
| #108 | Prod pipeline | Path confinement, pending_limitations |
| #109 | Hetzner live | Auth security signals; SSH still blocked |
| #110 | Diagnostics | `/v1/diagnostics/*` admin gate |

**Stack:** C12 → C11 → C10 → C9 → C8 → C7 → multi-agent → pedelec

**Prod surface (REPO + prior LIVE):**
- App: `/opt/scootercheck/firmware-analysis` · uvicorn `127.0.0.1:8088`
- systemd: `scootercheck-fw.service`
- nginx: `snippets/scootercheck-fw.conf` → `https://api.tuningscanner.de/scootercheck-fw`
- Data (never sync-delete): `/var/lib/scootercheck/{firmware-jobs,decrypted,decompiled,stock-fw}`
- Secrets outside releases: `/etc/scootercheck/firmware-analysis.env`, `decrypt.env`
- Existing scripts: `deploy/phase1-rollout.sh` (CONFIRM_PROD_DEPLOY gate, currently `root@` + `StrictHostKeyChecking=accept-new`), `install-on-hetzner.sh`
- CI today: iOS XCTest only (no dedicated server Python workflow yet)
- SSH from Cloud VM: **blocked** (no deploy key) — Cycle 10 confirmed

**CI gate note:** Server deploy must not require green iOS as sole gate; add server-tests job + optional iOS.

## Agent deliverables

| Agent | Branch pattern | Output |
|-------|----------------|--------|
| A DevOps | `cursor/c12-devops-deploy-b100` | `deploy-hetzner.yml`, remote release/rollback scripts |
| B Server Architect | `cursor/c12-server-compat-b100` | Compat checklist, deps, worker/TEA/Ghidra config validation |
| C Security | `cursor/c12-deploy-security-b100` | Secrets model, least-privilege SSH user, Freigabe |
| D QA | `cursor/c12-deploy-qa-b100` | Smoke tests, rollback tests, CI gate matrix |

Grades: DEPLOYED ≠ AVAILABLE ≠ TESTED ≠ END_TO_END_VERIFIED  
No real tuning files in selftests.
