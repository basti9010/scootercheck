# ScooterCheck AI Bridge (Etappe 1–3)

Development Automation bridge between LLM hosts (ChatGPT MCP, Cursor) and ScooterCheck task/CI orchestration.

| Path | Owner | Notes |
|------|-------|-------|
| `ai_bridge/` | Agent A | Orchestrator core — do not overwrite from Agent B |
| `schemas/`, `tests/` (root) | Agent A | Task schema, state machine, mock E2E |
| `mcp/` | Agent B+F | Tool surface, authz roles, security gates |

**CURSOR_API_LIVE_VERIFIED = false** unless a real `CURSOR_API_KEY` is present **and** a successful live call against `https://api.cursor.com` has been explicitly verified. This package never flips that flag from mocks.

**Claims:** MCP code here ≠ `CHATGPT_CONNECTION_VERIFIED`.  
**Deploy:** No production deploy tools; Hetzner stays on GitHub Environment approval.

## Layout

```
services/ai-bridge/
  schemas/task.schema.json
  ai_bridge/   # models, state_machine, store, planner, cursor_client, orchestrator, app
  mcp/         # Agent B MCP surface
  tests/       # Agent A pytest (state machine, idempotency, mock E2E)
  data/        # local runtime store (gitignored contents)
```

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `CURSOR_API_KEY` | only for live | User/service API key from Cursor Dashboard. **Never commit.** |
| `CURSOR_API_BASE` | no | Default `https://api.cursor.com` |
| `AI_BRIDGE_DATA_DIR` | no | Task/report store root (default `./data`) |
| `AI_BRIDGE_USE_LIVE` | no | `true` to use RealCursorClient (needs key) |
| `AI_BRIDGE_AUTO_APPROVE` | no | Default `true`; set `false` to stop at WAITING_FOR_APPROVAL |

Auth for live API: Bearer or Basic with the API key (see [Cloud Agents API](https://cursor.com/docs/cloud-agent/api/endpoints)).

## Task statuses

`CREATED` → `VALIDATING` → `PLANNED` → (`WAITING_FOR_APPROVAL`) → `QUEUED` → `RUNNING` → `TESTING` → `REVIEW` → `COMPLETED`

Also: `BLOCKED`, `FAILED`, `CANCELLED` (see `ai_bridge/state_machine.py`).

## Mock E2E (no API key)

```bash
cd services/ai-bridge
pip install -r requirements.txt
python3 -m pytest -q tests
python3 -m ai_bridge.run_mock_e2e
```

Expected: task reaches `COMPLETED`, report JSON under `data/reports/`, and `CURSOR_API_LIVE_VERIFIED` remains **false**.

## FastAPI (optional)

```bash
cd services/ai-bridge
uvicorn ai_bridge.app:app --reload --port 8090
# POST /orchestrate with TaskCreate JSON
# POST /webhooks/cursor/status-change  (stub)
```

## Live Cursor

Without a key, `RealCursorClient.from_env()` returns `None` and live paths are skipped. Do **not** claim `CURSOR_API_LIVE_VERIFIED` from mock runs.
