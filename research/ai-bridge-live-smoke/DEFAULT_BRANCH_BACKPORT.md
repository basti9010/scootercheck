# Ursache: Workflow nicht in Actions sichtbar

**Default branch:** `cursor/testflight-ci-133a`  
**Live-Smoke-Datei vorhanden auf:** `cursor/ai-bridge-v2-b100` (nach Merge PR #120)  
**Live-Smoke-Datei auf Default:** fehlte (404)

## Warum

GitHub zeigt Workflows mit `workflow_dispatch` in der Actions-UI („Run workflow“) erst, wenn die Workflow-Datei auf dem **Standardbranch** liegt.  
PR #120 hat den Workflow nur in die Linie `#118 → #119 → cursor/ai-bridge-v2-b100` gemergt — nicht in `cursor/testflight-ci-133a`.

Zusätzlich: Der Live-Smoke wurde noch nie ausgeführt; er war daher auch nicht als „bekannter“ Workflow aus einem früheren Run registriert.

## Abhängigkeiten

| PR | Status | Relevanz |
|----|--------|----------|
| #118 | open | AI Bridge 1.0 Basis (nicht in Default) |
| #119 | open | AI Bridge 2.0 (Base von #120) |
| #120 | **merged** in #119-Head | Live-Smoke Workflow + Harness |

Dieser Backport bringt **nur** die für den Live-Smoke benötigten, bereits geprüften Pfade auf den Default-Branch:

- `.github/workflows/ai-bridge-live-smoke.yml`
- `.github/workflows/ai-bridge-tests.yml` (Regression CI)
- `services/ai-bridge/` (RealCursorClient + Harness + Tests)
- `research/ai-bridge-live-smoke/`

**Nicht** enthalten: Hetzner-Deploy-Änderungen, Demo-Bypass (#114), iOS-App-Änderungen, Secret-/Environment-Policy-Änderungen.

## Sicherheit

- Trigger nur `workflow_dispatch`
- `environment: production` für `CURSOR_API_KEY`
- `permissions: contents: read`
- Confirm-Gate `confirm_live == LIVE`
- Kein Secret-Echo, kein `set -x`, kein Deploy/SSH
- Live-Test startet **nicht** durch diesen PR allein

## Merge

Nur nach ausdrücklicher Freigabe des Owners in den Standardbranch.
