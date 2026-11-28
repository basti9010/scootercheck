# Decisions (locked)

Inventory of product/security decisions evidenced in code/docs on this lineage. Not aspirational roadmap items.

## Product posture

1. **Read-only diagnosis** — No speed/limit writes, no firmware flash, no unlock combo execution. Soft-unlock UI is detection/documentation only (`BleWriteGate` default deny).
2. **ZIP ≠ installed FW** — Imported packages are artifacts; never equate to vehicle-installed firmware without separate BLE evidence.
3. **Epistemic honesty** — Prefer CONFIRMED / HYPOTHESIS / INCOMPLETE / NOT VERIFIED over marketing “green” claims.
4. **One correlator layer** — Cross-source hints reuse existing engines; do not invent a second verdict engine.

## Branch / merge policy

5. Work on `cursor/*` feature branches; **no merge to `main` without explicit Freigabe**.
6. **PR #114 (demo login bypass) must not be merged** into lasting product lines.
7. **PR #117 (auth recovery)** is the login-repair line: owner device-tested; CI/merge still independent verification.
8. Do not touch #114 demo bypass code while working Automation / deploy / memory tasks.

## Server / deploy

9. **No autonomous production deploy** — `deploy-hetzner.yml` is `workflow_dispatch` only; Environment `production` + `confirm_deploy` + human reviewers.
10. **Server CI blocks server deploy**; iOS XCTest is intentionally non-blocking for firmware-analysis CD.
11. **Immutable SHA deploy** — refuse branch tips; releases under `/opt/scootercheck/releases/<sha>/` with symlink flip; never sync-delete `/var/lib/scootercheck`.
12. **Host key checking stays on** — `StrictHostKeyChecking=yes` + pinned `known_hosts`; never `accept-new` / `no`.
13. **No shell HTTP API** — subprocess helpers use fixed argv, `shell=False`; reject remote-exec features.
14. **Diagnostics = true admin only** — JWT `role=admin` or `ADMIN_API_TOKEN`; shared `API_TOKEN` must not elevate via `API_TOKEN_GRANTS_ADMIN`.
15. **Secrets never in git/logs** — env on host only; health/diagnostics expose configured flags, not values.

## Firmware forensics

16. **Defensive analysis only** — document manipulation indicators; do not implement illegal tuning activation / limit unlock tooling.
17. Encrypted analysis without decrypt capability remains **INCOMPLETE** (not silent success).
18. Ghidra/TEA live E2E requires host Freigabe; synthetic/fixture tests ≠ prod verification.

## Automation / memory

19. **Git / CI / deploy remain source of truth**; `development-memory/` is derived. Conflicts → `KNOWN_ISSUES.md`.
20. Never claim `CHATGPT_CONNECTION_VERIFIED` or Cursor live API verified from mocks or docs alone.
