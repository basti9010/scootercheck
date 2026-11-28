# AI Bridge 2.0 — Deployment Readiness (Hetzner)

**PRODUCTION_DEPLOYED = false** — no production deploy in this cycle.

## Service shape

- Separate systemd unit (suggested name: `scootercheck-ai-bridge.service`)
- Dedicated system user (e.g. `aibridge`) — no shared root with firmware-analysis
- Working directory: `/opt/scootercheck/ai-bridge`
- Data: `/var/lib/scootercheck/ai-bridge/` (SQLite + reports)
- Bind: loopback or private interface; TLS via reverse proxy (Caddy/nginx)

## Required secrets (server EnvironmentFile only)

Place in e.g. `/etc/scootercheck/ai-bridge.env` (mode `0600`, owner root / group aibridge):

| Variable | Purpose |
|----------|---------|
| `CURSOR_API_KEY` | Cursor Cloud Agents API (Dashboard → API Keys) |
| `AIBRIDGE_TOKENS` | JSON map of opaque bearer → `{sub, role}` |
| `AIBRIDGE_WEBHOOK_SECRET` | Optional Cursor/legacy webhook bearer |
| `GITHUB_TOKEN` | Fine-scoped read for PR/CI status (prefer GitHub App later) |
| `AI_BRIDGE_CORS_ORIGINS` | Explicit allowlist (empty = no CORS middleware) |
| `AI_BRIDGE_USE_LIVE` | `true` only after key is present and owner approves live mode |
| `AI_BRIDGE_USE_SQLITE` | `1` (default) |
| `AI_BRIDGE_DB_PATH` | `/var/lib/scootercheck/ai-bridge/ai_bridge.sqlite3` |
| `AI_BRIDGE_DATA_DIR` | `/var/lib/scootercheck/ai-bridge` |

**Never** put `CURSOR_API_KEY` in iOS, dashboard JS, git, Issues, or chat.

## Health

- `GET /health` — liveness (no secrets)
- Authenticated `GET /api/v1/status` — operational dashboard feed

## Backup / rollback

- Backup: copy SQLite + `reports/` (WAL mode — checkpoint before copy)
- Rollback: previous container/unit package + restore DB snapshot
- Product deploys remain **GitHub Environment–gated** (`deploy-hetzner.yml`) — AI Bridge must not trigger prod deploy

## First live smoke (owner)

1. Set `CURSOR_API_KEY` in the EnvironmentFile.
2. Set `AI_BRIDGE_USE_LIVE=true`.
3. Restart unit.
4. Run: `PYTHONPATH=. python -m ai_bridge.run_live_smoke`
5. Confirm evidence JSON shows `CURSOR_API_LIVE_VERIFIED: true` and a non-`bc-mock-` agent id.

## Mobile access (after HTTPS publish)

1. Open `https://<bridge-host>/` in Safari on iPhone.
2. Tap **Tok** → enter a bridge bearer from `AIBRIDGE_TOKENS` (not Cursor key).
3. Create task → Analysieren → Freigeben → Agent starten.
