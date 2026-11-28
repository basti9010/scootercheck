# Cycle 13 – Ops-Freigabe (kein Secret im Chat)

Nur nach ausdrücklicher Benutzerfreigabe ausführen.

## 1. Env-Keys prüfen (Namen only)

```bash
sudo /opt/scootercheck/firmware-analysis/deploy/audit-env-key-names.sh
# oder manuell: nur Key-Namen in /etc/scootercheck/*.env anzeigen
```

Erwartet:

- `API_TOKEN_GRANTS_ADMIN=0`
- `ADMIN_API_TOKEN` vorhanden (langer Zufallswert)
- Keine Hyphen-Varianten (`API-TOKEN-…`)

## 2. Admin-Token setzen + Restart

```bash
# Wert lokal generieren, z.B. openssl rand -hex 32
# In die Service-Env schreiben (Pfad laut Host-Layout), dann:
sudo systemctl restart scootercheck-fw
curl -fsS https://api.tuningscanner.de/scootercheck-fw/health | jq '{adminApiTokenConfigured,apiTokenGrantsAdmin,authMode}'
```

Erwartung: `adminApiTokenConfigured=true`, `apiTokenGrantsAdmin=false`, `authMode=separated`.

## 3. Ghidra Selftest (bevorzugt Host-CLI)

```bash
cd /opt/scootercheck/firmware-analysis
sudo -u scootercheck ./.venv/bin/python diagnostics_ghidra.py | tee /tmp/ghidra-c13-$(date +%Y%m%d).json
```

Pass: `executed=true`, `grades.verified=true`, `grades.endToEndVerified=true`.

## 4. Alternativ Admin-API

```bash
BASE=https://api.tuningscanner.de/scootercheck-fw
# Token nur lokal; nie in Tickets/Chat
curl -sS -X POST "$BASE/v1/diagnostics/selftest" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  -d '{"includeTea":true,"includeGhidra":true,"includeWorkers":true}'
# jobId pollen → result.steps[id=ghidra].executionVerified == true
```

## 5. Optional Deploy-Smoke mit Selftest

```bash
SMOKE_ADMIN_TOKEN=… SMOKE_GHIDRA_SELFTEST=1 \
  ./deploy/post-deploy-smoke.sh
```

GRADE `Ghidra_selftest=VERIFIED` nur bei echter API-Antwort.
