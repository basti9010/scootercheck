# iPhone-Anleitung — Cursor Live Smoke starten

Kein SSH. Kein API-Key kopieren. Keine Serverdateien bearbeiten.

**Voraussetzungen**

1. Der Live-Smoke-Workflow liegt auf dem **Standardbranch** `cursor/testflight-ci-133a` (sonst erscheint er nicht in der Actions-Liste).
2. GitHub Environment `production` enthält Secret `CURSOR_API_KEY` (bereits hinterlegt).
3. Du bist auf dem iPhone in Safari bei GitHub angemeldet (Owner/Admin).

## Schritte (Safari)

1. Safari öffnen.
2. Repository öffnen: `https://github.com/basti9010/scootercheck`
3. Unten/Menü **Actions** tippen.  
   Falls die mobile UI Actions nicht zeigt: **Aa** → **Desktop-Website anfordern**, dann erneut **Actions**.
4. Links (oder Menü) Workflow **„AI Bridge Live Smoke (Cursor API)“** wählen.
5. **Run workflow** tippen.
6. Branch: **`cursor/testflight-ci-133a`** (Standardbranch) wählen.
7. Eingabe **confirm_live**: genau `LIVE` tippen (Großbuchstaben).
8. **starting_ref**: `cursor/testflight-ci-133a` (oder den Branch, den der Cursor-Agent als Basis nutzen soll).
9. **Run workflow** bestätigen.
10. Wenn GitHub eine **Environment-Freigabe** für `production` verlangt: Freigabe in der Wait-for-approval-Ansicht bestätigen.
11. Lauf abwarten (Polling bis Timeout ~10 min bei Default 60×10 s).
12. Unter dem Lauf → **Artifacts** → `scootercheck-cursor-live-smoke` herunterladen.
13. `LIVE_RESULT.json` / `LIVE_RESULT.md` öffnen und prüfen:
    - `CURSOR_API_LIVE_VERIFIED` = true
    - `cursor_agent_id` beginnt **nicht** mit `bc-mock-`
    - optional `CURSOR_AGENT_COMPLETED` = true wenn der Agent fertig wurde

## Was du nicht tun musst

- Keinen Cursor-API-Key anfassen
- Kein Terminal / SSH
- Kein Hetzner-Deploy

## Bei Problemen

- `confirm_live` nicht `LIVE` → Workflow bricht absichtlich ab, kein API-Call.
- Secret leer → Step „Assert CURSOR_API_KEY present“ schlägt fehl (ohne Key-Ausgabe).
- Timeout → `final_status` / `RESULT_STATUS` = `UNKNOWN`, Agent-ID bleibt erhalten; Agent kann remote noch laufen.
