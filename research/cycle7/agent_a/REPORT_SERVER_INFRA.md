# Agent A – Server Infrastructure (PM interim)

Source: `origin/cursor/unified-investigation-flow-b100:server/firmware-analysis/` (now ported to this branch).

## Present on unified / now in tree
- FastAPI app `app.py` — jobs upload/poll, auth (API token + Bearer JWT), admin stock
- `DECRYPT_CMD` → external **ninebottea** wrapper (not shipped; no keys in repo)
- Optional Ghidra headless, radare2, capstone, yara, unicorn/angr
- `.env.example` placeholders only

## Absent on this Cloud VM
- `GHIDRA_HOME` / `analyzeHeadless`
- ninebottea binary / vehicle keys
- Live deploy credentials → connectivity to `api.tuningscanner.de` **INCOMPLETE** without secrets

## Recommendations
1. Keep server tree in-repo; configure secrets via host env / Cursor secrets — never git
2. Health endpoint for capability flags
3. Encrypted uploads only decrypt server-side when DECRYPT_CMD configured
