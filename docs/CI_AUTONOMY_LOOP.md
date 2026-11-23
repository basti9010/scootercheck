# ScooterCheck – CI Autonomy Loop

**Cycle:** 5 (P0 Final Verification & P1 Development)  
**Max auto-fix attempts per distinct failure:** 3 (fresh budget; Cycle 4 exhausted)  
**Branch:** `cursor/multi-agent-system-b100` (never force `main`)

## Pipeline

Workflow: `.github/workflows/ios-unit-tests.yml`

| Item | Value |
|------|--------|
| Runner | `macos-15` |
| Xcode | Prefer **16.2** (Codemagic baseline); else newest 16.x on runner |
| Project | `ios/ScooterCheck/ScooterCheck.xcodeproj` |
| Scheme | `ScooterCheck` (shared, with `ScooterCheckTests` Testable) |
| Destination | iOS Simulator (iPhone 16 → 15 fallback) |
| Signing | `CODE_SIGNING_ALLOWED=NO` (unit tests only) |
| Triggers | PR / push (paths `ios/ScooterCheck/**`, workflow) / `workflow_dispatch` |
| Artifacts | logs + `.xcresult` (14 days) |

Deployment target from project: **iOS 16.0**, Swift **5.0**.  
TestFlight workflow separately may require newer App Store SDKs — **unit tests do not**.

## Fix loop (PM-coordinated)

1. Implementer agent changes code (worktree if file-isolated).
2. QA agent reviews (explore / security-review).
3. Push → GitHub Actions runs build + XCTest.
4. On failure: PM reads check logs / artifacts; opens `CI-FIX-n` task in `AGENT_TASK_QUEUE.md`.
5. Responsible specialist gets a correction prompt (max **3** attempts for the same root cause).
6. Re-push → re-test.
7. After 3 failed attempts → status **BLOCKED** with evidence; no silent inventing of green builds.

## Cycle lock

Only one autonomy cycle owns CI fix loops on this branch. Check `AGENT_TASK_QUEUE.md` lock before starting parallel timers.

## Honesty rules

- Never claim tests passed without CI or local macOS `xcodebuild` output.
- Linux Cloud Agent cannot run XCTest — mark **UNVERIFIED** until CI reports.
