# ChatGPT → ScooterCheck AI Bridge — Einrichtungsanleitung

Keine zusätzliche Website. Steuerung nur über ChatGPT + MCP.

## Voraussetzungen

1. Öffentlicher **HTTPS**-Endpunkt der AI Bridge MCP (oder OpenAI Secure MCP Tunnel).
2. Env auf dem Server (nie in Chat/Git):
   - `CURSOR_API_KEY` (bereits für Live-Smoke bewährt)
   - `AIBRIDGE_OWNER_APPROVE_TOKEN` (OAuth-Freigabe im Browser)
   - `AIBRIDGE_AUTH_SERVER` = öffentliche Basis-URL des Auth-Servers (gleiche Origin ok)
   - `AIBRIDGE_MCP_RESOURCE` = `https://<host>/mcp`
   - `AI_BRIDGE_USE_LIVE=true` nur wenn Cursor-Starts erlaubt
   - `AI_BRIDGE_MCP_USE_BRIDGE=1`
3. ChatGPT-Konto mit Recht, **Custom MCP / Plugins** hinzuzufügen (Plus/Pro/Business/Enterprise/Edu — **ACCOUNT_AVAILABLE**).

## MCP-Endpunkte

| Pfad | Zweck |
|------|--------|
| `POST https://<host>/mcp` | Streamable HTTP MCP (initialize, tools/list, tools/call) |
| `GET /.well-known/oauth-protected-resource` | Resource-Metadaten |
| `GET /.well-known/oauth-authorization-server` | OAuth 2.1 AS Metadaten (PKCE S256) |
| `GET /oauth/authorize` | Owner-Freigabe (Owner-Token) |
| `POST /oauth/token` | Code → Access Token |
| `GET /health` | Liveness (keine Secrets) |

## Plugin in ChatGPT registrieren (Web / Safari)

1. Browser (auf dem iPhone: **Safari**, nicht die ChatGPT-App für die Einrichtung).
2. `https://chatgpt.com/plugins` öffnen und anmelden.
3. **+** → **Add custom MCP server**.
4. Name: `ScooterCheck`.
5. Server URL: `https://<host>/mcp`.
6. Authentication: **OAuth**.
7. Risiko-Hinweis bestätigen → Create as a plugin → Install.
8. OAuth-Fenster: Owner-Token (`AIBRIDGE_OWNER_APPROVE_TOKEN`) eingeben → Freigeben.
9. Neuen Chat öffnen → `@` → **ScooterCheck**.

> Die ChatGPT-iPhone-App hat oft **keinen** „Add server“-Screen. Einrichtung im Browser; Nutzung danach in der App mit demselben Account (**ACCOUNT_AVAILABLE**).

## Lesender Test

```text
@ScooterCheck Nutze nur scootercheck_status und zeige den Projektstand.
Keine Schreibaktionen.
```

Erwartung: PRs/CI/Tasks ohne Secrets; `chatgpt_connection_verified` im Tool-Rohdaten-Feld bleibt bis zur erfolgreichen Registrierung getrennt dokumentiert.

## Schreibender Test (nach Bestätigung in ChatGPT)

```text
@ScooterCheck Erstelle mit scootercheck_create_task einen harmlosen Auftrag:
„Erstelle eine kurze technische Markdown-Dokumentation unter research/chatgpt-native/.“
Zeige task_id und Plan. Starte noch nichts.
```

Nach Freigabe in ChatGPT (Write-Confirm):

```text
Starte den Auftrag mit scootercheck_start_task und der task_id.
Danach scootercheck_task_status und scootercheck_task_report.
```

Nur wenn dieser Ablauf in **dieser** ChatGPT-Session mit echtem Cursor-Agent gelingt:

`CHATGPT_TO_CURSOR_E2E_VERIFIED=true`

## Sicherheit

- Cursor-API-Key bleibt nur auf dem Server.
- Schreibtools brauchen OAuth-Bearer + Rolle + ChatGPT-Bestätigung.
- Kein Deploy-Tool; Prod-Deploy weiter nur GitHub Environment `production`.
- Limits: `AIBRIDGE_MAX_CONCURRENT_AGENTS`, `AIBRIDGE_MAX_STARTS_PER_HOUR`.

## Wenn die Verbindung scheitert

Dokumentiere die konkrete Meldung (Plan/Workspace/Lockdown/DNS/TLS/OAuth).  
Nicht auf inoffizielle APIs oder ein Dashboard ausweichen.
