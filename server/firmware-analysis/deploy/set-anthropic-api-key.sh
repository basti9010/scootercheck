#!/usr/bin/env bash
# Set a Claude Console API key into firmware-analysis.env without echoing it.
# Usage: setllmkey
set -euo pipefail
ENV_FILE=/etc/scootercheck/firmware-analysis.env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

echo "Paste Claude API key (sk-ant-usr… or sk-ant-api…), then Enter."
echo "Input hidden. Console may turn '-' into 'ß' — we auto-fix that."
read -r -s KEY
echo
KEY=$(printf '%s' "$KEY" | tr -d '\r\n' | xargs)

# Hetzner console DE-layout mangling
KEY=${KEY//ß/-}
KEY=${KEY//ÃŸ/-}
KEY=${KEY// /}

if [[ -z "$KEY" ]]; then
  echo "Empty key — aborted." >&2
  exit 1
fi

if [[ "$KEY" == sk-ant-oat* ]]; then
  echo "ERROR: sk-ant-oat is an OAuth/setup token, not a Console API key." >&2
  exit 1
fi

if [[ "$KEY" != sk-ant-usr* && "$KEY" != sk-ant-api* && "$KEY" != sk-ant-* ]]; then
  echo "ERROR: Key should start with sk-ant-usr or sk-ant-api (got prefix: ${KEY:0:14}…)" >&2
  exit 1
fi

umask 077
tmp=$(mktemp)
awk -v key="$KEY" '
  BEGIN{done=0}
  /^LLM_API_KEY=/ { print "LLM_API_KEY=" key; done=1; next }
  { print }
  END{ if(!done) print "LLM_API_KEY=" key }
' "$ENV_FILE" >"$tmp"
grep -q '^LLM_PROVIDER=' "$tmp" || echo 'LLM_PROVIDER=anthropic' >>"$tmp"
grep -q '^LLM_BASE_URL=' "$tmp" || echo 'LLM_BASE_URL=https://api.anthropic.com' >>"$tmp"
sed -i 's|^LLM_PROVIDER=.*|LLM_PROVIDER=anthropic|' "$tmp"
sed -i 's|^LLM_BASE_URL=.*|LLM_BASE_URL=https://api.anthropic.com|' "$tmp"
awk '
  /^LLM_MODEL=/ { if (++m>1) next }
  { print }
' "$tmp" >"${tmp}.2"
if ! grep -q '^LLM_MODEL=' "${tmp}.2"; then
  echo 'LLM_MODEL=claude-haiku-4-5-20251001' >>"${tmp}.2"
fi
install -m 600 "${tmp}.2" "$ENV_FILE"
rm -f "$tmp" "${tmp}.2"

systemctl restart scootercheck-fw
sleep 1

# Quick live auth probe (does not print the key)
python3 - <<'PY'
import json, os, urllib.request, urllib.error
from pathlib import Path
key=""
for line in Path("/etc/scootercheck/firmware-analysis.env").read_text().splitlines():
    if line.startswith("LLM_API_KEY="):
        key=line.split("=",1)[1].strip()
key=key.replace("ß","-")
body=json.dumps({"model":"claude-haiku-4-5-20251001","max_tokens":8,"messages":[{"role":"user","content":"ping"}]}).encode()
req=urllib.request.Request(
    "https://api.anthropic.com/v1/messages",
    data=body,
    headers={
        "Authorization": f"Bearer {key}",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    },
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        print("API_PROBE_OK", resp.status)
except urllib.error.HTTPError as e:
    print("API_PROBE_FAIL", e.code, e.read()[:160].decode(errors="replace"))
PY

curl -sS http://127.0.0.1:8088/health | python3 -c 'import sys,json;d=json.load(sys.stdin);print("llmConfigured=",d.get("llmConfigured"));print("llmKeyStatus=",d.get("llmKeyStatus"));print("llmProvider=",d.get("llmProvider"))'
echo "Done. Do not paste the key into chat."
