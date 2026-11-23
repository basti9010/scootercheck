# Phase 2.2H — Rollback-Plan (kein Produktivtest)

## Auslöser

- Healthcheck nach Restart schlägt fehl
- Import-/Unit-Tests auf dem Remote schlagen fehl
- Auth-Regression (z. B. Admin-Endpunkte unerreichbar trotz `ADMIN_API_TOKEN`)

## Schritte (manuell, nur mit Freigabe)

1. **Backup-Pfad** aus dem Rollout-Log: `/opt/scootercheck/firmware-analysis.bak-fw-<UTC-stamp>`
2. `systemctl stop scootercheck-fw`
3. Code zurückspielen: `rm -rf /opt/scootercheck/firmware-analysis && mv <backup> /opt/scootercheck/firmware-analysis`
4. Env unverändert lassen unter `/etc/scootercheck/firmware-analysis.env` (Jobs/Kataloge/Tokens bleiben)
5. `systemctl start scootercheck-fw`
6. `curl -fsS http://127.0.0.1:8088/health` → `ok: true`
7. **Nicht** löschen: `/var/lib/scootercheck/{firmware-jobs,decrypted,decompiled,stock-fw}`

## Was Rollback NICHT anfasst

- Produktivjobs
- Referenzfirmwares / Kataloge
- Auth-Secrets (nur Code-Tree)

## Dry-Run Nachweis

`CONFIRM_PROD_DEPLOY` unset/`NO` → `deploy/phase1-rollout.sh` führt nur lokale Checks aus und schreibt nichts remote.
