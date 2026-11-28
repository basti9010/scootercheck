# ai-bridge MCP — Security Notes (Agent B+F)

## Authz

| Rule | Enforcement |
|------|-------------|
| No anonymous write | All tool calls require bearer token (`401` if missing/invalid) |
| Role gates | `READ` / `TASK_WRITE` / `APPROVAL` / `ADMIN` via `roles.can_invoke` → `403` |
| No deploy tool | `FORBIDDEN_TOOL_NAMES` rejects SSH/deploy/shell helpers |
| Prod deploy | **GitHub Environment `production` approval only** — never via MCP |

## Secrets

- Tool results pass through `sanitize_tool_payload` / `redact_secrets`.
- Never return `AIBRIDGE_TOKENS`, API tokens, PEMs, JWT secrets, or GitHub Environment secret values.
- Health endpoints report booleans only (`chatgpt_connection_verified: false`).

## Prompt injection

- GitHub Actions / CI log excerpts are wrapped with `untrusted_external_text`.
- LLM hosts and humans must treat `log.text` as data, not instructions.
- `prepare_fix` records intent only; it does not merge PRs or dispatch deploy.

## ChatGPT / OAuth (documented, not fully hosted in Phase A)

- Custom MCP: ChatGPT Plugins → Add custom MCP server; SSE or streaming HTTP.
- OAuth 2.1 + MCP auth spec; publish `/.well-known/oauth-protected-resource`.
- PKCE S256; redirect `https://chatgpt.com/connector_platform_oauth_redirect` (or connector callback form).
- Workspace permissions / Lockdown may block custom MCP → **ACCOUNT_DEPENDENT**.
- Scaffold alone ≠ `CHATGPT_CONNECTION_VERIFIED`.

## QA checklist

- [ ] `401` without `Authorization` on `/mcp/tools/call` and `/tools/{name}`
- [ ] `401` with garbage token
- [ ] `READ` can `get_project_status` / `list_tasks` / `get_ci_status`
- [ ] `READ` cannot `start_task` / `create_task` / `cancel_task` → `403`
- [ ] `TASK_WRITE` can create/start/cancel; cannot `prepare_fix` → `403`
- [ ] `APPROVAL` can `prepare_fix`; cannot `start_task` → `403`
- [ ] `ADMIN` can all tools
- [ ] CI excerpt marked `untrusted: true` and secrets redacted
- [ ] No tool named deploy/ssh/shell exposed in `/mcp/tools`
- [ ] Docs do not claim ChatGPT connection verified
