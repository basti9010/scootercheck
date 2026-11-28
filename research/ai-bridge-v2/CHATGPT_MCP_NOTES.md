# ChatGPT / MCP readiness notes

**CHATGPT_CONNECTION_VERIFIED = false**  
**MCP_CLIENT_VERIFIED = false**  
**CHATGPT_TO_CURSOR_E2E_VERIFIED = false**

## Documented OpenAI path (as of research date 2026-11-28)

- Custom MCP connectors for ChatGPT require a remote MCP server with OAuth 2.1 (PKCE S256) and protected-resource metadata.
- Stable redirect documented for connectors: `https://chatgpt.com/connector_platform_oauth_redirect`
- Plan/availability for private user connectors depends on OpenAI product tier (Pro/Team/Enterprise/Work) — **not verified for this owner's account in this cycle**.
- iOS ChatGPT may require connector setup completed in browser first — **not device-verified here**.

## ScooterCheck implementation

- Tools: nine `scootercheck_*` tools with input schemas + role gates (`services/ai-bridge/mcp/tools.py`)
- Transport today: FastAPI JSON (`/mcp/tools`, `/mcp/tools/call`) + OAuth protected-resource stub
- Optional shared backend: `AI_BRIDGE_MCP_USE_BRIDGE=1` → `BridgeBackend` (same SQLite/orchestrator as HTTP API)
- Bearer role tokens via `AIBRIDGE_TOKENS` for authz exercises — **not** a full IdP

## Alternative client

Until ChatGPT OAuth is wired and verified, the **Mobile Development Center** (`services/ai-bridge/dashboard/`) is the supported control surface against the same `/api/v1` API.
