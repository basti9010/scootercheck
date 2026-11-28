---
name: scootercheck-release
description: Prepare ScooterCheck releases (TestFlight notes, server CD dry-runs, versioned SHA packaging) with human confirm gates — never autonomous production deploy.
---

# scootercheck-release

## Purpose

Coordinate release readiness: immutable SHA selection, CI gates, TestFlight vs Hetzner paths, rollback awareness — without performing unauthorized prod deploys.

## When to use

- Cutting a candidate SHA for firmware-analysis CD.
- TestFlight build checklist (`docs/TESTFLIGHT.md`).
- Validating `deploy/validate-release-config.sh` / smoke logic.
- Writing release notes / Abschlussbericht sections.

## Inputs

- Candidate full 40-char git SHA.
- CI status for `Server Firmware Tests` (required for server CD) and optional iOS XCTest.
- `docs/HETZNER_DEPLOYMENT_SETUP.md`, `deploy/ci-gate-matrix.md`, `DEPLOYMENT_STATUS.md`.
- PR constraints (#114 ban; #117 auth line separate).

## Workflow

1. Confirm SHA is immutable and on the intended lineage.
2. Require green **Server Firmware Tests** for that SHA before recommending CD.
3. Prefer `confirm_deploy=false` / remote dry-run first; list ops checklist items still open.
4. For iOS: point to TestFlight workflow / Codemagic; do not conflate with server CD.
5. Document rollback: automatic on smoke fail; manual `release-rollback.sh`.
6. Update `DEPLOYMENT_STATUS.md` only with evidence (dry-run vs DEPLOYED).
7. Never approve GitHub Environment `production` from an unattended agent.

## Outputs

- Release checklist with SHA, CI run ids, residual ops tasks.
- Optional script dry-run logs (no live mutate).

## Safety limits

- **No autonomous production deploy.**
- Do not skip CI gate except documented emergency + human Freigabe.
- Do not disable host key checking.
- Do not promote PR #114 demo builds as lasting releases.
- Do not claim END_TO_END_VERIFIED or DEPLOYED without host smoke + Freigabe.
