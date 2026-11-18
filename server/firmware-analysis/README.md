# Firmware-Analyse-Worker (ScooterCheck)

Nimmt ZIP/ENC von der App entgegen, speichert Jobs strukturiert, ruft **ninebottea** (`DECRYPT_CMD`) auf, optional **Ghidra Headless**, und liefert ein `FirmwareDeepAnalysisResult`-JSON zurück.

Dieses Repo enthält **kein** ninebottea und **keine** Keys.

## Ablauf

1. App `POST /v1/firmware/jobs` (multipart: `meta_json` + `archive`) — Antwort sofort `queued`
2. Worker speichert unter `WORK_DIR/YYYY/MM/DD/<jobId>/`
3. Background: extract `.enc` → `DECRYPT_CMD` → Klartext unter `PLAINTEXT_STORE/YYYY/MM/DD/`
4. Optional Ghidra → `.c` unter `DECOMPILE_STORE/YYYY/MM/DD/`
5. Speed-/Combo-Scan (deterministisch) → JSON
6. Optional KI (`allowLLM` + `LLM_API_KEY`): schema-gebundene Anreicherung von Combos/Modi/Eingaben aus dem Decompile-Snippet (keine neuen Speeds)
7. App pollt `GET /v1/firmware/jobs/{id}` bis `completed` / `failed`
8. Optional Download: `/plaintext`, `/decompile`

## KI (Schritt 1 der Analyse-Erweiterung)

In `/etc/scootercheck/firmware-analysis.env`:

```bash
LLM_API_KEY=sk-...
LLM_BASE_URL=https://api.openai.com/v1   # oder kompatibler Proxy
LLM_MODEL=gpt-4o-mini
```

Dann `systemctl restart scootercheck-fw`. `GET /health` → `llmConfigured: true`. Ohne Key läuft die Pipeline unverändert (Note `llm=skipped`).

## Stock-Diff (Schritt 2)

Nach Decrypt vergleicht der Worker den Klartext mit `/var/lib/scootercheck/stock-fw/` (ENV `STOCK_FW_DIR`).

- Dateien: `*.bin` / `*.dec.bin`, optional `manifest.json`
- Admin: `GET/POST/DELETE /v1/firmware/admin/stock`
- Ergebnis im Job: `result.stockDiff` (`identical` | `different` | `noReference`)

Ohne Referenzen: `noReference` — Pipeline sonst unverändert.

## radare2 (Schritt 3)

Nach Decrypt, vor Ghidra: `r2` sucht packed Speed-Immediates (`/x`) und interessante Strings (`izz`).

```bash
apt-get install -y radare2
# optional: ENABLE_R2=0 zum Abschalten
```

`GET /health` → `r2Configured: true`. Quelle in der App: „Server-radare2“.

## Ghidra Speed-Xrefs / Capstone / YARA (Schritt 4–6)

- Ghidra `ExportSpeedXrefs.java` schreibt `.speeds.json` (Listing-Immediates → Function/Addr)
- Capstone: ARM/Thumb-Disasm auf packed Speeds (`pip install capstone`)
- YARA: `yara_rules/scooter_cfw.yar` (`pip install yara-python`)

Health: `capstoneConfigured`, `yaraConfigured`. Abschaltbar via `ENABLE_CAPSTONE=0` / `ENABLE_YARA=0`.

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
