# Firmware-Analyse-Worker (ScooterCheck)

Nimmt ZIP/ENC von der App entgegen, speichert Jobs strukturiert, ruft **ninebottea** (`DECRYPT_CMD`) auf, optional **Ghidra Headless**, und liefert ein `FirmwareDeepAnalysisResult`-JSON zurück.

Dieses Repo enthält **kein** ninebottea und **keine** Keys.

## Ablauf

1. App `POST /v1/firmware/jobs` (multipart: `meta_json` + `archive`) — Antwort sofort `queued`
2. Worker speichert unter `WORK_DIR/YYYY/MM/DD/<jobId>/`
3. Background: extract `.enc` → `DECRYPT_CMD` → Klartext unter `PLAINTEXT_STORE/YYYY/MM/DD/`
4. Optional Ghidra → `.c` unter `DECOMPILE_STORE/YYYY/MM/DD/`
5. Speed-/Combo-Scan (deterministisch) → JSON
6. Optional KI (`allowLLM`, Default **false**, + `LLM_API_KEY`): schema-gebundene Anreicherung von Combos/Modi/Eingaben aus dem Decompile-Snippet (keine neuen Speeds). Ohne KI bleibt die Pipeline vollständig funktionsfähig.
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

- Dateien: `*.bin` / `*.dec.bin`, `manifest.json` mit `source` (`oem`|`serial`|`unknown`|`case`), optional `models[]`/`region`/`notes`
- Vergleich nutzt **nur** `source=oem|serial` (Fall-Uploads werden ignoriert)
- Bei gesetztem `models`/`controllerType`: **strict match** — kein Cross-Model-Fallback (z. B. ZT3 → ehrlich `noReference`)
- Ergebnis: `result.stockDiff` (`identical` | `different` | `noReference`) inkl. `referenceLabel`, `differingBytes`, `limitRegionAffected`, `panicRegionAffected`, `candidateRefCount`
- Admin: `GET/POST/DELETE /v1/firmware/admin/stock` — Upload braucht `confirmOem=true` für OEM/Serial
- Promote: `POST .../promote-stock?confirmOem=true` — lehnt hohe CFW-YARA-Treffer ab
- Rexzy67-Import: `import_rexzy_stock.py` / `alias_rexzy_stock.py` → OEM-Refs aus `x3-firmware-archive`

Ohne passende trusted Referenzen: `noReference` — Pipeline sonst unverändert. Keine erfundenen Tastenkombis (`combo_policy`).

## Cortex-M IVT (Schritt 2b)

Nach Decrypt: Heuristik auf Vektortabelle (SP in SRAM, Reset Thumb in Flash). Ergebnis in `result.cortexMIvt`. Unicorn startet optional am Reset; angr nutzt Reset als `entry_point`.

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
- YARA: `yara_rules/scooter_cfw.yar` — Speed-Immediates, PanicSystem, ScooterHacking/SHFW, ESC-CFW, Region-Hints (`pip install yara-python`)

Health: `capstoneConfigured`, `yaraConfigured`. Abschaltbar via `ENABLE_CAPSTONE=0` / `ENABLE_YARA=0`.

## Phase 2 — Funktionsanalyse / Callgraph / Function-Diff

Zusätzlich zu Decompile/Xrefs (Phase 1 bleibt unverändert):

- `ExportFunctionAnalysis.java` → `FIRM.functions.json` (Adresse, Größe, CFG, Calls, Konstanten/Strings, Fingerprint)
- `ExportCallGraph.java` → `FIRM.callgraph.json` (+ optionales `.dot`-Stub ohne Extra-Deps)
- `function_diff.py` vergleicht Subject vs. optionale Referenz-`*.functions.json`  
  Status: `IDENTISCH` | `STRUKTURELL_VERAENDERT` | `HINZUGEFUEGT` | `ENTFERNT` | `NICHT_VERGLEICHBAR`  
  **Kein Diaphora/BinDiff** (Lizenz/RAM/Headless) — strukturelle Änderung ≠ Manipulation
- Poll-Payload trägt nur Summaries (`functionAnalysis`, `functionDiff`, `callGraph`, `referenceMetadata`, `analysisLimitations`)
- Vollartefakte (auth):  
  `GET /v1/firmware/jobs/{id}/functions` · `/callgraph` · `/function-diff`
- LLM bleibt opt-in (`allowLLM=false`); `llm_verify.py` streicht unbelegte Adress-/FUN_-Claims
- Limits: `GHIDRA_MAX_FUNCTIONS`, bestehendes `HEAVY_ANALYSIS_LOCK`, best-effort bei Export-Fehlern

## Limit-Slice / Pinout / Input-Probe (Kombi-Forensik)

Nach Speed-Scan:

1. **ExportLimitFunctions.java** — Ghidra decompiliert nur Funktionen mit Speed-Immediates (+ Caller) → `.limits.c` (bessere KI-/Combo-Qualität)
2. **limit_slice** — Capstone-Rückwärts von Limit-Stores zu cmp/ldr; mappt Adressen über `board_pinouts.py` (ZT3 AT32, G3, F3…)
3. **input_probe** — kurze Unicorn-Fenster mit Dual-Hebel-Registerpresets; meldet Sensitivität als Hypothese

Alles investigativ — kein Beweis ohne Live-Vergleichstest. Abschaltbar: `ENABLE_LIMIT_SLICE=0`, `ENABLE_INPUT_PROBE=0`.

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

## Auth (Phase 2.1 / 2.2B / 2.2H / 2.2H.2)

- `Authorization: Bearer <ScooterCheck-JWT>` (User muss `active` sein) — gleicher `JWT_SECRET` wie Auth-API; **preferred owner** `user:<sub>`
- und/oder `X-ScooterCheck-Token` wenn `API_TOKEN` / `ADMIN_API_TOKEN` gesetzt
- `X-ScooterCheck-Client-Id` is **metadata only** under secure defaults (not a trusted principal)
- Admin: JWT `role=admin` **oder** `ADMIN_API_TOKEN`
- **Phase 2.2H secure default:** `API_TOKEN_GRANTS_ADMIN=0` — shared `API_TOKEN` does **not** grant admin
- Legacy opt-in only: `API_TOKEN_GRANTS_ADMIN=1` (discouraged; staging/new deploys keep `0`)
- **Phase 2.2H.1:** `TRUST_API_TOKEN_CLIENT_ID=0` — Client-Id must **not** own/access jobs under shared token (spoofable). Prefer Bearer JWT for user jobs.
- Legacy opt-in only: `TRUST_API_TOKEN_CLIENT_ID=1` (discouraged)
- Bearer JWT is preferred over shared token when both headers are present
- **Phase 2.2H.2:** iOS stores JWT in Keychain; firmware upload/poll/artifacts require Bearer JWT. `/health` exposes `authSecurityOk` / `authSecurityWarnings`.
- Ops before next prod restart: set `ADMIN_API_TOKEN`, confirm `API_TOKEN_GRANTS_ADMIN=0` and `TRUST_API_TOKEN_CLIENT_ID=0`

## Firmware-Identität / Auto-Funktionen (Phase 2.2B)

- `firmware_identify.py` plausibilisiert Cortex-M-IVT (SP/Reset/Thumb) und schlägt Processor + Base vor — unsichere Layouts werden als `architectureUnknown` markiert
- Ghidra `-preScript SeedCortexMEntryPoints.java` setzt IVT-Entry-Points (Thumb-Kontext), folgt Calls und scanned Literal-Pool-Thumb-Pointer (ohne manuelle Adressliste)
- Optional weiterhin `CreateKnownThumbFunctions.java` nur für Ground-Truth-Validierung
- ENV: `GHIDRA_AUTO_IDENTIFY=1` (Default), `GHIDRA_SEED_IVT=1` (Default)

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
