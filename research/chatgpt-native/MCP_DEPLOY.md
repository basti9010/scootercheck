# MCP Deployment readiness (no auto-deploy)

Separate from Hetzner firmware-analysis deploy.

Suggested unit: `scootercheck-ai-bridge-mcp.service`

```text
WorkingDirectory=/opt/scootercheck/ai-bridge
ExecStart=uvicorn mcp.server:app --host 127.0.0.1 --port 8787
EnvironmentFile=/etc/scootercheck/ai-bridge-mcp.env
```

Reverse proxy TLS → `127.0.0.1:8787` with paths `/mcp`, `/.well-known/*`, `/oauth/*`, `/health`.

Do **not** expose write tools without OAuth. Do **not** put `CURSOR_API_KEY` in ChatGPT.

Production start only after explicit Freigabe.
