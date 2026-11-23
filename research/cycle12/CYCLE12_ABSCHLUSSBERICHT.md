# SCOOTERCHECK – CYCLE 12 ABSCHLUSSBERICHT

Stand: 2026-11-23 Europe/Berlin  
Branch: `cursor/hetzner-deploy-cd-c12-b100`  
PR: https://github.com/basti9010/scootercheck/pull/112  
(Hinweis: #111 war merged markiert, C11-Force-Push entfernte Commits → Restack als #112)

## 1. Subagents

| Agent | ID |
|-------|-----|
| DevOps | bc-7bed6f1b-08ca-5cd6-8a62-4da5b2f2cd28 |
| Server Architect | bc-8e189f48-c255-5b3c-aa6e-d0a7bc42834e |
| Security | bc-06750ab0-443e-51c7-98d1-6cdb8e800403 |
| QA | bc-30df8ac0-fd91-52a1-a664-fa5b61f6d59a |

## 2–4. Workflow / Sicherheit / Ablauf

- `.github/workflows/deploy-hetzner.yml` — nur `workflow_dispatch`, Environment `production`, immutable SHA, Server-CI-Gate, `StrictHostKeyChecking=yes`
- `.github/workflows/server-firmware-tests.yml` — Pflicht für Server-Deploy (iOS optional)
- Secrets: `HETZNER_SSH_*` nur in Environment; kein Key im Repo
- Deploy-User least-privilege (`bootstrap-deploy-user.sh`, default dry-run)

## 5–7. Backup / Rollback / Tests

- Releases unter `/opt/scootercheck/releases/<sha>/`, Symlink flip; `/var/lib/scootercheck` unberührt; `/etc/scootercheck` unberührt
- `release-rollback.sh` + Smoke-Fail → Workflow Rollback
- Lokal: **46** deploy/manifest/smoke Tests OK

## 8–10. CI / User / Bereitschaft

- CI tip: pending on #112; older tip `e25d4cd` had 2 checks green (pre-restack)
- User einmalig: siehe `docs/HETZNER_DEPLOYMENT_SETUP.md` (Checklisten **offen**)
- DEPLOYED: **nein** (kein SSH Freigabe / kein Live-Deploy)
- END_TO_END_VERIFIED: **nein**

## Einfache Übersicht

**FERTIG:** CD-Workflow, Scripts, Docs, Server-Testgate, Agent-Ingests  
**USER EINMALIG:** Environment `production`, Secrets, Deploy-User, Host-Keys, Auth härten  
**DEPLOY STARTEN:** Actions → Deploy Hetzner → SHA + confirm_deploy=true → Freigabe tippen  
**ROLLBACK:** automatisch bei Smoke-Fail oder `release-rollback.sh` mit CONFIRM_PROD_DEPLOY=YES
