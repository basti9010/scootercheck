# Firmware-Analyse-Worker (ScooterCheck)

Nimmt ZIP/ENC von der App entgegen, speichert Jobs strukturiert, ruft **ninebottea** (`DECRYPT_CMD`) auf, optional **Ghidra Headless**, und liefert ein `FirmwareDeepAnalysisResult`-JSON zurück.

Dieses Repo enthält **kein** ninebottea und **keine** Keys.

## Ablauf

1. App `POST /v1/firmware/jobs` (multipart: `meta_json` + `archive`) — Antwort sofort `queued`
2. Worker speichert unter `WORK_DIR/YYYY/MM/DD/<jobId>/`
3. Background: extract `.enc` → `DECRYPT_CMD` → Klartext unter `PLAINTEXT_STORE/YYYY/MM/DD/`
4. Optional Ghidra → `.c` unter `DECOMPILE_STORE/YYYY/MM/DD/`
5. Speed-Scan → JSON in Job-Status
6. App pollt `GET /v1/firmware/jobs/{id}` bis `completed` / `failed`
7. Optional Download: `/plaintext`, `/decompile`

## Auth

- `Authorization: Bearer <ScooterCheck-JWT>` (User muss `active` sein) — gleicher `JWT_SECRET` wie Auth-API
- und/oder `X-ScooterCheck-Token` wenn `API_TOKEN` gesetzt

## Hetzner

```bash
sudo mkdir -p /opt/scootercheck
sudo rsync -a server/firmware-analysis/ /opt/scootercheck/firmware-analysis/
sudo bash /opt/scootercheck/firmware-analysis/deploy/install-on-hetzner.sh
# nginx:
#   include /etc/nginx/snippets/scootercheck-fw.conf;
sudo nginx -t && sudo systemctl reload nginx
```

App-Default: `https://api.tuningscanner.de/scootercheck-fw`

## ENV

Siehe `.env.example` und `/etc/scootercheck/firmware-analysis.env`.
