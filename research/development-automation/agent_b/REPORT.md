# Agent B+F Report — MCP + Security Foundation

**Branch:** `cursor/development-automation-b100`  
**Role:** ChatGPT/OpenAI MCP docs, capability matrix (incl. GitHub/Hetzner), MCP scaffold, authz tests  
**Claim ban honored:** `CHATGPT_CONNECTION_VERIFIED` = **false / not claimed**

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Phase A architecture inventory | `research/development-automation/ARCHITECTURE_INVENTORY.md` | Done |
| API capability matrix | `research/development-automation/API_CAPABILITY_MATRIX.md` | Done |
| Alt path (Dev Center) | `research/development-automation/ALTERNATIVE_PATH_DEV_CENTER.md` | Done |
| MCP tool surface + auth | `services/ai-bridge/mcp/` | Done (stubs) |
| Security notes + QA checklist | `services/ai-bridge/mcp/SECURITY.md` | Done |
| Authz pytest | `services/ai-bridge/mcp/tests/test_authz_gates.py` | **14 passed** |
| This report | `research/development-automation/agent_b/REPORT.md` | Done |

Coordination: Agent A owns `services/ai-bridge/ai_bridge/` orchestrator core — **not overwritten**. MCP uses `orchestrator_stubs.MockOrchestrator` until wired.

## Matrix summary

| Surface | Documented | Available-in-account | Implemented-in-repo | Live-tested |
|---------|------------|----------------------|---------------------|-------------|
| Cursor API / Cloud Agents | Partial/YES | UNKNOWN / ACCOUNT_DEPENDENT | Partial | NO |
| ChatGPT custom MCP | YES (official) | ACCOUNT_DEPENDENT (Lockdown/workspace) | Scaffold | NO |
| GitHub Actions / Env deploy gate | YES | UNKNOWN | YES (workflows) | NO |
| Hetzner CD via Actions | YES | UNKNOWN | YES (scripts+workflow) | NO |
| ai-bridge MCP tools (9) | YES | N/A local | YES | YES (pytest) |

ChatGPT facts recorded from official docs: Plugins → Add custom MCP; SSE / streaming HTTP; OAuth / no-auth / mixed; OAuth 2.1 + MCP auth; `/.well-known/oauth-protected-resource`; PKCE S256; redirect `https://chatgpt.com/connector_platform_oauth_redirect`. Workspace Lockdown → ACCOUNT_DEPENDENT. MCP server ≠ chat connection verified.

## Tool list (roles)

| Tool | Role |
|------|------|
| `scootercheck_get_project_status` | READ |
| `scootercheck_list_tasks` | READ |
| `scootercheck_get_task_status` | READ |
| `scootercheck_get_task_report` | READ |
| `scootercheck_get_ci_status` | READ (CI text → untrusted envelope) |
| `scootercheck_create_task` | TASK_WRITE |
| `scootercheck_start_task` | TASK_WRITE |
| `scootercheck_cancel_task` | TASK_WRITE |
| `scootercheck_prepare_fix` | APPROVAL (no deploy) |

No deploy/SSH/shell tools. Production deploy remains GitHub Environment approval only.

## Security notes (short)

- No anonymous write; missing/invalid token → **401**
- Insufficient role → **403** (READ cannot `start_task`)
- Secrets redacted in tool results
- GH/CI text tagged `untrusted` + prompt-injection warning
- Health always reports `chatgpt_connection_verified: false`

## Test results

```text
cd services/ai-bridge && python3 -m pytest mcp/tests/test_authz_gates.py -v
14 passed
```

Key cases: `test_missing_token_is_401`, `test_read_cannot_start_task`, `test_http_401_and_403_via_fastapi`, CI redaction, nine-tool catalog without deploy.

## Commits

Primary commit: `7af228f18f7186ac052d245db6fce84a8a7f5b86` (this report updated in follow-up if needed).
