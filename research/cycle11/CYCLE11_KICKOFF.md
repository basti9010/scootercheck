# Cycle 11 Kickoff — Server Diagnostics, Remote Validation & Automated Forensic Testing

Stand: 2026-11-23 Europe/Berlin  
Base: `cursor/hetzner-ghidra-live-c10-b100` @ `e7bfbbd`  
Branch: `cursor/server-diagnostics-c11-b100`

## Grades (mandatory)

CONFIGURED ≠ AVAILABLE ≠ VERIFIED ≠ FAILED ≠ UNKNOWN  
Flags alone never equal VERIFIED / END_TO_END_VERIFIED.

## Reuse

- `/health` flags (extend carefully, no secrets)
- Admin JWT / ADMIN_API_TOKEN gates (not shared API token admin)
- `DECRYPT_CMD` wrapper probe (no decrypt of real packs)
- Ghidra synthetic fixtures (cycle9/10)
- `FirmwareServerAnalysisClient` + AppSettings + InvestigationStore

## File ownership (avoid collisions)

| Agent | Own |
|-------|-----|
| A | `research/cycle11/agent_a/` + propose `diagnostics_models.py` API shape |
| B | `diagnostics_tea.py` + tests + report |
| C | `diagnostics_ghidra.py` + fixtures + tests + report |
| D | iOS Diagnostics UI/client + report |

PM merges routes into `app.py` after A–C.

## Policy

Admin-only diagnostics · no shell API · no env dump · no keys · no prod deploy without Freigabe · max 4 agents
