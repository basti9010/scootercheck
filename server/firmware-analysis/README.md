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
# Anthropic (Claude Console — Guthaben/API-Key)
LLM_PROVIDER=anthropic
LLM_API_KEY=sk-ant-...
LLM_BASE_URL=https://api.anthropic.com
LLM_MODEL=claude-haiku-4-5-20251001

# oder OpenAI-kompatibel:
# LLM_PROVIDER=openai
# LLM_API_KEY=sk-...
# LLM_BASE_URL=https://api.openai.com/v1
# LLM_MODEL=gpt-4o-mini
```

Dann `systemctl restart scootercheck-fw`. `GET /health` → `llmConfigured: true`, `llmProvider`. Ohne Key: Note `llm=skipped`.

API-Key in der Claude Console unter **API-Keys** anlegen (`sk-ant-usr…` oder `sk-ant-api…`; nicht OAuth `sk-ant-oat…`, nicht Cursor-Account-Key). Auf dem Server: `setllmkey` (normalisiert Hetzner-Konsolen-`ß`→`-`). Key nie in Chat/Git legen.

## Stock-Diff (Schritt 2)

Nach Decrypt vergleicht der Worker den Klartext mit `/var/lib/scootercheck/stock-fw/` (ENV `STOCK_FW_DIR`).

- Dateien: `*.bin` / `*.dec.bin`, optional `manifest.json`
- Admin: `GET/POST/DELETE /v1/firmware/admin/stock`
- Ergebnis im Job: `result.stockDiff` (`identical` | `different` | `noReference`)
- **Nur echte OEM-/Serien-Klartexte** als Stock hinterlegen. Fall-Uploads (z. B. dieselbe ZT3-ZIP) nicht als Referenz „promoten“ — sonst wirkt jeder Re-Upload fälschlich „Stock identisch“.

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

## Unicorn + Pfadanalyse (Schritt 7–8)

- **Unicorn**: kurze Emulation um Speed-Immediates (`pip install unicorn`, `ENABLE_UNICORN=0` zum Abschalten)
- **angr_lite**: Capstone-Rückwärts-Pfadanalyse; optionales **angr CFGFast-deep** in Subprozess
- Stock-Lib befüllen: Admin **→ Stock** auf einem Job mit Klartext, oder Dateien nach `STOCK_FW_DIR`

### angr ohne VPS-Crash

```bash
pip install angr   # im firmware-analysis venv
# /etc/scootercheck/firmware-analysis.env:
ENABLE_ANGR=1
ANGR_MAX_BYTES=262144      # nur kleine VCU-Bins
ANGR_TIMEOUT_SEC=150       # Parent killt Worker
ANGR_MEM_MB=1800           # RLIMIT_AS im Worker
ANGR_CFG_DEPTH=6           # multi-hop CFG-Vorgänger
ANGR_SYMBOLIC=0            # 1 = kurze Local-Explore je Speed-Site
```

- **CFGFast-deep**: data refs, indirect jumps, XRefs, Caller-Kette, Disasm-Snippet
- Optional `ANGR_SYMBOLIC=1`: begrenzte Exploration nur um Speed-Sites (nicht Full-Binary SE)
- Eigener Prozess + RAM-Cap + Timeout
- Gleiches Lock wie Ghidra (nie parallel)
- Bei Timeout/OOM: Capstone-Hints bleiben, Job wird `completed` (kein Hard-Fail)

Health: `unicornConfigured`, `angrLiteConfigured`, `angrEngineConfigured`, `angrTimeoutSec`, `angrMemMb`, `angrCfgDepth`, `angrSymbolic`.

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
