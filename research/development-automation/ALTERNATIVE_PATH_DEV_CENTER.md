# Alternative Path — Mobile Web Development Center

**When to use:** ChatGPT custom MCP is unavailable (workspace Lockdown, plan limits, OAuth blocked, or plugin install refused). Mark that situation **ACCOUNT_DEPENDENT**, not a ScooterCheck code failure.

**Do not claim:** `CHATGPT_CONNECTION_VERIFIED`. This path also does not prove ChatGPT connectivity.

---

## Idea

A mobile-friendly **Development Center** web UI (iPad Safari) that calls the **same** ai-bridge APIs the MCP tools wrap:

| UI action | Same backend tool / method |
|-----------|----------------------------|
| Project overview | `scootercheck_get_project_status` |
| Task board | `scootercheck_list_tasks` |
| Create task | `scootercheck_create_task` |
| Start / cancel | `scootercheck_start_task` / `scootercheck_cancel_task` |
| Task detail / report | `scootercheck_get_task_status` / `scootercheck_get_task_report` |
| CI strip | `scootercheck_get_ci_status` |
| Prepare fix (gated) | `scootercheck_prepare_fix` |

Auth: same bearer roles (`READ` / `TASK_WRITE` / `APPROVAL` / `ADMIN`). No anonymous write.

---

## Why this works without ChatGPT

1. MCP is a **transport + discovery** layer for LLM hosts.  
2. The durable contract is the **tool surface + authz** in `services/ai-bridge/mcp/`.  
3. A thin HTML/HTMX or SwiftUI WebView client can POST JSON to `/tools/{name}` with the same tokens.  
4. Agent A’s orchestrator core stays behind those interfaces either way.

---

## UX constraints (iPad-first)

- Large tap targets; one primary action per screen.  
- Write actions require explicit confirm (mirror ChatGPT write confirmation).  
- CI / GitHub text shown inside an “untrusted content” panel (prompt-injection hygiene for humans + any later LLM assist).  
- **No Deploy button** that SSHs to Hetzner — deep-link to GitHub Actions `workflow_dispatch` only; Environment approval remains human.

---

## Phase A status

| Item | Status |
|------|--------|
| API parity design | Documented here |
| MCP HTTP tool dispatch | Scaffolded (`services/ai-bridge/mcp`) |
| Production Dev Center UI | **Not built** this cycle (optional Agent C/UI follow-up) |
| Hosting | Prefer same auth boundary as ai-bridge; never embed long-lived admin tokens in the SPA |

---

## Fallback ladder

1. Try ChatGPT custom MCP (if account allows).  
2. Else Development Center (same APIs).  
3. Else Cursor Cloud Agents + GitHub UI (manual).  
4. Production deploy: **always** GitHub Environment approval — never skipped by (1)–(3).
