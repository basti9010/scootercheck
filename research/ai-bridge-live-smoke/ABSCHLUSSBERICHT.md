# AI Bridge 2.1 — Abschlussbericht (Cursor Live Smoke Workflow)

**Zeit (Europe/Berlin):** 2026-11-28  
**Branch:** `cursor/ai-bridge-live-smoke-b100`  
**Basis:** `cursor/ai-bridge-v2-b100` (PR #119)  
**Live-Test durch Agent:** **nicht gestartet** (nur Owner nach Review/Merge)

---

## 1. Entwicklungsstand

### Implementierte Dateien

| Datei | Zweck |
|-------|--------|
| `.github/workflows/ai-bridge-live-smoke.yml` | `workflow_dispatch`-only Live-Smoke |
| `services/ai-bridge/ai_bridge/run_live_smoke.py` | RealCursorClient harness + Polling + Reports |
| `services/ai-bridge/ai_bridge/live_status.py` | Status-Mapping Cursor → Report |
| `services/ai-bridge/tests/test_live_smoke_harness.py` | Unit/Integration (Fake client) |
| `services/ai-bridge/tests/test_workflow_live_smoke_security.py` | Workflow-Security-Static |
| `research/ai-bridge-live-smoke/*` | Docs, Placeholder-Reports, iPhone-Anleitung |

Bestehende Bridge wiederverwendet — keine zweite API-Implementierung.

## 2. Workflow

| Item | Wert |
|------|------|
| Trigger | **nur** `workflow_dispatch` |
| Environment | `production` → `secrets.CURSOR_API_KEY` |
| Permissions | `contents: read` |
| Confirm-Gate | Input `confirm_live` muss exakt `LIVE` sein |
| Concurrency | `ai-bridge-live-smoke-production`, `cancel-in-progress: false` |
| Artifact | `scootercheck-cursor-live-smoke`, retention 7 Tage |
| Deploy | **kein** Hetzner / SSH |

### Environment-Schutz (Ist-Zustand)

- Environment `production` existiert und hat mindestens eine Protection Rule.
- `deployment_branch_policy` war bei der Prüfung **null** (keine Branch-Einschränkung sichtbar).
- **Benutzeraktion:** Settings → Environments → production → Deployment branches auf den gemergten Standard-/Freigabe-Branch einschränken.
- Secrets und bestehende Deploy-Freigaben wurden **nicht** geändert.

### Restrisiko Idempotenz

Cursor `POST /v1/agents` ist nicht idempotent. Gegenmaßnahmen: Concurrency-Lock, `idempotency_state.json` pro Run, Resume ohne zweiten Create. Harter Abbruch zwischen Create und State-Write kann trotzdem einen Doppelagenten erzeugen — Workflow nicht leichtfertig erneut starten.

## 3. Cursor API

| Item | Wert |
|------|------|
| Auth | Bearer `CURSOR_API_KEY` (serverseitig in Actions) |
| Start | `POST https://api.cursor.com/v1/agents` |
| Status | `GET /v1/agents/{id}/runs/{runId}` |
| Cancel | dokumentiert; Smoke pollt bis Terminal/Timeout |
| Retries | vorhandener RealCursorClient (429/5xx) |
| Live in diesem PR | **nicht ausgeführt** |

## 4. Tests

| Suite | Ergebnis |
|-------|----------|
| AI Bridge + MCP pytest | **72 passed** (lokal) |
| Live smoke blocked / harness / workflow security | enthalten |
| GitHub Actions Live-Smoke | **noch nicht vom Owner gestartet** |

## 5. Live-Verifikation

| Frage | Antwort |
|-------|---------|
| Echte Agent-ID erhalten? | **noch nicht** (Owner-Lauf ausstehend) |
| Status erfolgreich abgerufen? | ausstehend |
| Agent erfolgreich abgeschlossen? | ausstehend |
| Pull Request durch Cursor erstellt? | ausstehend |

## 6. Benutzeraktionen (konkret)

1. Diesen PR reviewen; CI (AI Bridge Tests) grün lassen.
2. Mergen in den gewünschten Freigabe-Branch.
3. Optional aber empfohlen: Environment `production` → Deployment branches einschränken.
4. iPhone: Anleitung in `IPHONE_ANLEITUNG.md` folgen (`confirm_live=LIVE`).
5. Artifact `scootercheck-cursor-live-smoke` öffnen → `LIVE_RESULT.json` prüfen.

## 7. Qualitätsstatus

```
WORKFLOW_IMPLEMENTED=true
WORKFLOW_CI_VERIFIED=false   # CI dieses PR-Branches nach Push prüfen
CURSOR_API_LIVE_VERIFIED=false
CURSOR_AGENT_COMPLETED=false
GITHUB_PR_CREATED=false      # Cursor-Agent-PR; dieser Implementierungs-PR ist separat
IPHONE_WORKFLOW_VERIFIED=false
```

`CURSOR_API_LIVE_VERIFIED=true` darf erst gesetzt werden, wenn der Owner-Lauf eine echte Agent-ID liefert und der Statusabruf gelingt.

Keine Secrets in diesem Bericht.
