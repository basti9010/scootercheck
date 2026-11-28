# Project State

**Inventory date:** 2026-11-28  
**Checkout branch:** `cursor/development-automation-b100`  
**Base lineage:** Cycle 12 `cursor/hetzner-deploy-cd-c12-b100` → C11 #110 → C10 #109 → … → multi-agent #103  
**Product rule:** read-only diagnosis — no limit writes, no flash, no unlock execution.

## Product (CONFIRMED on this checkout)

- Native iOS app SwiftUI + CoreBluetooth, bundle `com.scootercheck.app`
- Path: `ios/ScooterCheck/ScooterCheck.xcodeproj`
- Server: FastAPI firmware-analysis under `server/firmware-analysis/` (deploy target `/opt/scootercheck/firmware-analysis`)
- Catalog: `catalogs/stock-firmware.json`
- Custom agents: `.cursor/agents/*.md` (IDE); Cloud Task uses fixed `subagent_type` values

## Parallel PR lines (not merged into this checkout)

| PR | Branch | Status note |
|----|--------|-------------|
| **#117** | `cursor/p0-auth-recovery-b100` | P0 login repair. **Device-tested by owner** (login UX). Merge/CI must still be verified independently. Do not claim CI-green from this memory alone. |
| **#114** | `cursor/demo-skip-login-b100` | Demo login bypass (`authGateEnabled=false` + `DemoAuthBootstrap`). **Must not be merged.** Temporary presentation only. |
| #112 | `cursor/hetzner-deploy-cd-c12-b100` | Cycle 12 CD scaffolding (this lineage). |
| #103 | `cursor/multi-agent-system-b100` | Multi-agent + P0/P1 app foundation (historical green CI notes in `docs/`). |

## Auth / backend on this checkout

- `backend/app/` and `backend/tests/` contain **only** `__pycache__` here — **no `.py` sources** on this branch tip.
- Login/JWT UI and auth recovery live on the **#117** line (base `cursor/login-paste-caps-b100` / `cursor/backend-auth-b100`), not in this working tree.
- Treat auth as **INCOMPLETE on this checkout**; see `KNOWN_ISSUES.md`.

## Epistemic snapshot

| Claim | Label |
|-------|-------|
| iOS read-only diagnose app present | CONFIRMED |
| Server firmware-analysis + diagnostics modules present | CONFIRMED |
| Hetzner CD workflow present (dispatch-only) | CONFIRMED |
| Production deployed via CD | NOT VERIFIED / not done (setup checklist open) |
| Live Ghidra/TEA E2E on prod host | NOT VERIFIED (Freigabe / host gates) |
| ChatGPT / Cursor live API bridge | PLANNED — never claim verified from mocks |
| PR #117 device login OK | Owner-reported; CI/merge independent |
| PR #114 mergeable into lasting product | Forbidden |

## Automation 1.0 (this effort)

| Phase | Status |
|-------|--------|
| A – Architecture / bridge scaffolding | See `research/development-automation/` (other agents) |
| B – Project memory (`development-memory/`) | IMPLEMENTED (derived) |
| C – Cursor skills (`.cursor/skills/`) | IMPLEMENTED (docs) |
