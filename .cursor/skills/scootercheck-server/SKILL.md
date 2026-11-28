---
name: scootercheck-server
description: Work on ScooterCheck FastAPI firmware-analysis server — diagnostics, job auth, analysis modules, deploy scripts — without inventing a second architecture or live-deploying.
---

# scootercheck-server

## Purpose

Change `server/firmware-analysis/` safely: APIs, diagnostics, analysis helpers, and deploy tooling that match the existing Hetzner layout.

## When to use

- Diagnostics status/selftest (`diagnostics_*.py`).
- Job auth / path confinement / health flags.
- Analysis pipeline modules (function match/diff, semantic dataflow, combo policy, …).
- Deploy scripts under `deploy/` and CI gate workflow.

## Inputs

- Bug or feature scope.
- `docs/DEPLOY_SECURITY.md`, `docs/HETZNER_DEPLOYMENT_SETUP.md`, `deploy/RELEASE_COMPAT.md`.
- Memory: `ARCHITECTURE.md`, `DEPLOYMENT_STATUS.md`.

## Workflow

1. Confirm module ownership; prefer extending `app.py` routers / existing helpers.
2. Keep subprocess calls fixed-argv / `shell=False`; no caller-supplied shell.
3. Diagnostics must stay **true-admin** (`enforce_diagnostics_admin`) — refuse shared API token elevation.
4. Add pytest in `test_*.py` with fixtures under `testdata/` when possible.
5. Run targeted `pytest` locally; CI via `server-firmware-tests.yml`.
6. If touching deploy scripts: preserve symlink release layout; never delete `/var/lib/scootercheck`; default dry-run / confirm gates.
7. Update memory deploy/test status only with evidence.

## Outputs

- Server code + pytest.
- Notes on auth mode implications and deploy compatibility.

## Safety limits

- **No production deploy** from this skill; do not set `confirm_deploy=true`.
- No secrets in repo, logs, or health payloads.
- Do not claim Ghidra/TEA live E2E without Freigabe.
- Do not weaken `API_TOKEN_GRANTS_ADMIN=0` posture in defaults.
- Backend auth service sources may be on another branch (`backend/` empty of `.py` here).
