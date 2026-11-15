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


## Ablauf nach App-Upload

1. App lädt ZIP/ENC hoch  
2. Worker speichert Upload unter `WORK_DIR/<jobId>/`  
3. `DECRYPT_CMD` → Klartext unter `PLAINTEXT_STORE/… .dec.bin`  
4. Optional **Ghidra Headless** → Decompile unter `DECOMPILE_STORE/… .dec.c`  
5. Speed-Scan (BIN + `.c`) → JSON zurück  
6. Downloads: `/plaintext` und `/decompile`

### Ghidra auf dem Hetzner

```bash
# Ghidra nach /opt/ghidra entpacken, dann in firmware-analysis.env:
GHIDRA_HOME=/opt/ghidra
ENABLE_GHIDRA=1
# ARM Cortex-M / AT32-VCU Defaults:
GHIDRA_PROCESSOR=ARM:LE:32:Cortex
GHIDRA_BASE_ADDR=0x08000000
```

Skript: `ghidra_scripts/ExportAllDecompiled.java` (wird per `-postScript` ausgeführt).

## DECRYPT_CMD (ninebottea bereits installiert)

```bash
cp decrypt-firm.example.sh /opt/scootercheck/decrypt-firm.sh
chmod +x /opt/scootercheck/decrypt-firm.sh
# /etc/scootercheck/decrypt.env → NINEBOTTEA_BIN=/pfad/zu/ninebottea
# Bei Bedarf eine Zeile im Wrapper an eure CLI anpassen: "$BIN" decrypt "$IN" "$OUT"
export DECRYPT_CMD=/opt/scootercheck/decrypt-firm.sh
```

Keys nur in `decrypt.env` auf dem Hetzner-Host — nicht in Git.

## App

Einstellungen → Firmware-Analyse-Server: Basis-URL + Token.  
Firmware-Forensik → „Auf Server entschlüsseln / analysieren“.

## API

- `POST /v1/firmware/jobs` multipart: `meta_json` + `archive`
- `GET /v1/firmware/jobs/{id}`
- `GET /v1/firmware/jobs/{id}/plaintext` (gespeicherter Klartext)
- Header: `X-ScooterCheck-Token` wenn `API_TOKEN` gesetzt
