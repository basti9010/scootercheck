# ChatGPT Native Integration — Capability Audit

**Date (Europe/Berlin):** 2026-11-28  
**Sources (DOCUMENTED):** OpenAI developers docs — custom MCP server, plugin auth, MCP building guide; ChatGPT Learn MCP notes.

## Epistemic labels used here

| Label | Meaning |
|-------|---------|
| DOCUMENTED | Stated in official OpenAI docs we reviewed |
| ACCOUNT_AVAILABLE | Unknown for this owner until they try in their account |
| IMPLEMENTED | Present in ScooterCheck code |
| CONNECTED | ChatGPT successfully registered our MCP (not done in this cycle) |
| END_TO_END_VERIFIED | ChatGPT → Bridge → Cursor → GitHub proven in a chat (not done) |

## What ChatGPT supports (DOCUMENTED)

| Capability | Status |
|------------|--------|
| Custom remote MCP as ChatGPT plugin | DOCUMENTED |
| Transports: **SSE** and **streaming HTTP** | DOCUMENTED |
| Auth: OAuth, none, or mixed | DOCUMENTED |
| OAuth 2.1 + MCP auth spec (resource metadata, AS metadata, PKCE S256) | DOCUMENTED |
| Client registration: CIMD, DCR, or predefined client | DOCUMENTED |
| Redirect for connectors | DOCUMENTED form includes `https://chatgpt.com/connector_platform_oauth_redirect` |
| Write tools + confirmation UI | DOCUMENTED |
| `readOnlyHint` respected | DOCUMENTED |
| `search`/`fetch` required for custom MCP plugins | **DOCUMENTED: not required** for general custom MCP plugins (required for deep research / company knowledge style servers) |
| Add custom MCP on ChatGPT **web** | DOCUMENTED |
| Add custom MCP inside **iPhone ChatGPT app** | DOCUMENTED / third-party guides: **setup is web/Safari**; native app often has no add-server screen |
| Use installed plugin on iPhone after web setup | ACCOUNT_AVAILABLE (expected once installed on same account) |
| Paid plan required | DOCUMENTED / guides: Plus/Pro/Business/Enterprise/Edu commonly required; **ACCOUNT_AVAILABLE** for this owner |
| Workspace Lockdown may block custom MCP | DOCUMENTED |

## Owner questions A–E

| Question | Answer |
|----------|--------|
| A. Install with existing ChatGPT access? | **ACCOUNT_AVAILABLE** — needs paid plan + workspace permission; not verified for this account |
| B. Create development tasks? | **DOCUMENTED** write tools allowed with confirmation; **IMPLEMENTED** in Bridge tools; **CONNECTED** false |
| C. Start Cursor agents? | **IMPLEMENTED** via Bridge→RealCursorClient; ChatGPT can call write tool if connected; **E2E** false until ChatGPT connected |
| D. Return results into ChatGPT chat? | **DOCUMENTED** tool outputs shown in conversation |
| E. Usable on iPhone after setup? | Setup: **web/Safari**. Ongoing use: **ACCOUNT_AVAILABLE** (same account) |

## Already proven (prior cycle)

| Gate | Value |
|------|-------|
| CURSOR_API_LIVE_VERIFIED | true (GitHub Actions live smoke; agent `bc-2d348346-f60b-4bb9-92e5-1ee6d5119259`) |
| CHATGPT_CONNECTION_VERIFIED | false |
| CHATGPT_TO_CURSOR_E2E_VERIFIED | false |
| MCP_CLIENT_VERIFIED | false |

## Blockers to CONNECTED / E2E

1. Public HTTPS MCP URL (or Secure MCP Tunnel) must be deployed — **no prod deploy in this cycle without Freigabe**.
2. Owner must register the plugin at ChatGPT Plugins (web) and complete OAuth.
3. Account/plan/workspace may refuse custom MCP — only the owner can prove this.

## Non-goals this cycle

- No new Development Center / website
- No unofficial ChatGPT APIs
- No claiming CONNECTED without owner ChatGPT registration
