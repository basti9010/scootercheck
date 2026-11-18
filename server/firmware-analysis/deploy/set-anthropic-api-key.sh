#!/usr/bin/env bash
# Set a Claude Console API key (sk-ant-api…) into firmware-analysis.env without echoing it.
# Usage on the VPS:
#   sudo bash /opt/scootercheck/firmware-analysis/deploy/set-anthropic-api-key.sh
# then paste the key once and press Enter.
set -euo pipefail
ENV_FILE=/etc/scootercheck/firmware-analysis.env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi
echo "Paste Claude API key (sk-ant-api…), then Enter. Input is hidden."
read -r -s KEY
echo
KEY=$(printf '%s' "$KEY" | tr -d '\r\n' | xargs)
if [[ -z "$KEY" ]]; then
  echo "Empty key — aborted." >&2
  exit 1
fi
if [[ "$KEY" == sk-ant-usr* ]]; then
  echo "That looks like sk-ant-usr (Console/session), not an API key. Create one under API-Schlüssel." >&2
  exit 1
fi
if [[ "$KEY" != sk-ant-api* && "$KEY" != sk-ant-* ]]; then
  echo "Warning: key does not start with sk-ant-api / sk-ant- — continuing anyway."
fi
umask 077
tmp=$(mktemp)
awk -v key="$KEY" '
  BEGIN{done=0}
  /^LLM_API_KEY=/ { print "LLM_API_KEY=" key; done=1; next }
  { print }
  END{ if(!done) print "LLM_API_KEY=" key }
' "$ENV_FILE" >"$tmp"
# ensure provider/base
grep -q '^LLM_PROVIDER=' "$tmp" || echo 'LLM_PROVIDER=anthropic' >>"$tmp"
grep -q '^LLM_BASE_URL=' "$tmp" || echo 'LLM_BASE_URL=https://api.anthropic.com' >>"$tmp"
sed -i 's|^LLM_PROVIDER=.*|LLM_PROVIDER=anthropic|' "$tmp"
sed -i 's|^LLM_BASE_URL=.*|LLM_BASE_URL=https://api.anthropic.com|' "$tmp"
install -m 600 "$tmp" "$ENV_FILE"
rm -f "$tmp"
systemctl restart scootercheck-fw
sleep 1
curl -sS http://127.0.0.1:8088/health | python3 -c 'import sys,json;d=json.load(sys.stdin);print("llmConfigured=",d.get("llmConfigured"));print("llmKeyStatus=",d.get("llmKeyStatus"));print("llmProvider=",d.get("llmProvider"))'
echo "Done. Do not paste the key into chat."
