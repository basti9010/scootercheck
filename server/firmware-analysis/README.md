# Firmware-Analyse-Worker (ScooterCheck)

Nimmt ZIP/ENC von der App entgegen, ruft **euer bereits installiertes** Decrypt-Tool auf (`DECRYPT_CMD`) und liefert ein `FirmwareDeepAnalysisResult`-JSON (Speed-Signaturen).

Dieses Repo enthält **kein** ninebottea und **keine** Keys.

## Hetzner VPS (empfohlen)

Auf dem Hetzner-Server (als root), Repo-Pfad anpassen:

```bash
# Code hinlegen
sudo mkdir -p /opt/scootercheck
sudo rsync -a server/firmware-analysis/ /opt/scootercheck/firmware-analysis/

# Install + systemd
sudo bash /opt/scootercheck/firmware-analysis/deploy/install-on-hetzner.sh

# Decrypt-Wrapper (euer bereits installiertes Tool)
sudo cp /opt/scootercheck/firmware-analysis/decrypt-firm.example.sh /opt/scootercheck/decrypt-firm.sh
sudo nano /opt/scootercheck/decrypt-firm.sh   # euer Tool einbinden
sudo nano /etc/scootercheck/firmware-analysis.env  # API_TOKEN + DECRYPT_CMD

sudo systemctl restart scootercheck-fw
```

TLS: `deploy/nginx-fw.conf.example` + Certbot. In der App: `https://dein-hostname` + Token.

## Lokal starten

```bash
cd server/firmware-analysis
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # API_TOKEN + DECRYPT_CMD setzen
export $(grep -v '^#' .env | xargs)
uvicorn app:APP --host "${HOST:-127.0.0.1}" --port "${PORT:-8088}"
```


## DECRYPT_CMD

Skript mit zwei Argumenten: `input.enc` → `output.bin`.

```bash
cp decrypt-firm.example.sh /opt/scootercheck/decrypt-firm.sh
# Skript so anpassen, dass es EUER installiertes Tool aufruft (Key nur aus Vault/Env)
chmod +x /opt/scootercheck/decrypt-firm.sh
export DECRYPT_CMD=/opt/scootercheck/decrypt-firm.sh
```

## App

Einstellungen → Firmware-Analyse-Server: Basis-URL + Token.  
Firmware-Forensik → „Auf Server entschlüsseln / analysieren“.

## API

- `POST /v1/firmware/jobs` multipart: `meta_json` + `archive`
- `GET /v1/firmware/jobs/{id}`
- `GET /v1/firmware/jobs/{id}/plaintext` (Klartext-BIN, authentifiziert)
- Header: `X-ScooterCheck-Token` wenn `API_TOKEN` gesetzt
