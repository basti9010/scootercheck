# ai-bridge

Development Automation bridge between LLM hosts (ChatGPT MCP, Cursor) and ScooterCheck task/CI orchestration.

| Path | Owner | Notes |
|------|-------|-------|
| `ai_bridge/` | Agent A | Orchestrator core — do not overwrite from Agent B |
| `mcp/` | Agent B+F | Tool surface, authz roles, security gates |

**Claims:** MCP code here ≠ `CHATGPT_CONNECTION_VERIFIED`.  
**Deploy:** No production deploy tools; Hetzner stays on GitHub Environment approval.
