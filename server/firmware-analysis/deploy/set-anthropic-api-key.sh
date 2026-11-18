#!/usr/bin/env bash
# Set a Claude Console API key into firmware-analysis.env without echoing it.
# Usage: setllmkey
set -euo pipefail
ENV_FILE=/etc/scootercheck/firmware-analysis.env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

echo "Paste Claude API key (must start with sk-ant-api), then Enter."
echo "Input hidden. If console turns '-' into 'ß', we auto-fix that."
read -r -s KEY
echo
KEY=$(printf '%s' "$KEY" | tr -d '\r\n' | xargs)

# Hetzner console DE-layout mangling: '-' often becomes 'ß'
KEY=${KEY//ß/-}
KEY=${KEY//ÃŸ/-}

if [[ -z "$KEY" ]]; then
  echo "Empty key — aborted." >&2
  exit 1
fi

# Normalize accidental spaces
KEY=${KEY// /}

if [[ "$KEY" == sk-ant-usr* ]]; then
  echo "ERROR: That is sk-ant-usr (session/console), NOT an API key." >&2
  echo "In Claude Console → API-Schlüssel → create key, copy sk-ant-api… value." >&2
  exit 1
fi

if [[ "$KEY" != sk-ant-api* ]]; then
  echo "ERROR: Key must start with sk-ant-api… (got prefix: ${KEY:0:12}…)" >&2
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
# drop duplicate LLM_MODEL lines, keep first / set default
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
curl -sS http://127.0.0.1:8088/health | python3 -c 'import sys,json;d=json.load(sys.stdin);print("llmConfigured=",d.get("llmConfigured"));print("llmKeyStatus=",d.get("llmKeyStatus"));print("llmProvider=",d.get("llmProvider"))'
echo "Done. Do not paste the key into chat."
