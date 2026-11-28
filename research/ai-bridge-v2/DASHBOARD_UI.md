# Development Center UI (Agent D)

**Path:** `services/ai-bridge/dashboard/`  
**Branch:** `cursor/ai-bridge-v2-b100`  
**Target:** iPhone Safari — bg `#12161C`, accent `#6BDBC2`

## Screens

| Route hash | Purpose |
|------------|---------|
| `#/` | Home status (bridge / Cursor Live / ChatGPT / deploy) |
| `#/new` | Large textarea → `POST /api/v1/tasks` |
| `#/tasks` | Task list → `GET /api/v1/tasks` |
| `#/task/{id}` | Detail + approve / start |
| `#/task/{id}/report` | Report → `GET /api/v1/tasks/{id}/report` |

## Auth

- Bearer from `localStorage["aibridge_token"]` only.
- Never store or send Cursor API keys from the SPA.

## Honesty rules

- Missing data → `UNKNOWN` or `NOT VERIFIED`.
- No fake progress bars.
- Assets served at `/static/*` when the bridge mounts the dashboard.
