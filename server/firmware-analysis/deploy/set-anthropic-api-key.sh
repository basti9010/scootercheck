#!/usr/bin/env bash
# Set a Claude Console API key into firmware-analysis.env without echoing it.
# Usage:
#   setllmkey                 # paste raw key (SSH from your PC — best)
#   setllmkey --hex           # paste hex of the key — safest in Hetzner web console
#   setllmkey --b64           # paste base64 (fallback)
set -euo pipefail
ENV_FILE=/etc/scootercheck/firmware-analysis.env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

MODE=raw
case "${1:-}" in
  --hex|-hex) MODE=hex ;;
  --b64|-b64) MODE=b64 ;;
esac

case "$MODE" in
  hex)
    echo "Paste HEX of the Claude key, then Enter."
    echo "Windows PowerShell (only this line, no prompt):"
    echo "  ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes('sk-ant-…'))).Replace('-','').ToLower()"
    echo "Input hidden. Hex has only 0-9a-f — console-safe."
    ;;
  b64)
    echo "Paste BASE64 of the Claude key, then Enter."
    echo "Prefer: setllmkey --hex"
    echo "Input hidden."
    ;;
  *)
    echo "Paste Claude API key (sk-ant-usr… / sk-ant-api…), then Enter."
    echo "Prefer SSH from PC. In Hetzner web console use: setllmkey --hex"
    echo "Input hidden. Console may turn '-' into 'ß' — we auto-fix that."
    ;;
esac

read -r -s KEY
echo
KEY=$(printf '%s' "$KEY" | tr -d '\r\n \t')

if [[ -z "$KEY" ]]; then
  echo "Empty input — aborted." >&2
  exit 1
fi

if [[ "$MODE" == "hex" ]]; then
  KEY=$(printf '%s' "$KEY" | tr 'A-F' 'a-f')
  if [[ ! "$KEY" =~ ^[0-9a-f]+$ ]]; then
    echo "ERROR: not hex (only 0-9 a-f allowed). len=${#KEY}" >&2
    exit 1
  fi
  if (( ${#KEY} % 2 == 1 )); then
    echo "ERROR: hex length must be even (got ${#KEY})." >&2
    exit 1
  fi
  if ! KEY=$(printf '%s' "$KEY" | xxd -r -p 2>/dev/null | tr -d '\r\n'); then
    echo "ERROR: hex decode failed." >&2
    exit 1
  fi
elif [[ "$MODE" == "b64" ]]; then
  # strip whitespace; keep standard alphabet; add padding
  KEY=$(printf '%s' "$KEY" | tr -d '\r\n \t')
  pad=$(( (4 - ${#KEY} % 4) % 4 ))
  if (( pad > 0 )); then
    KEY="${KEY}$(printf '%*s' "$pad" '' | tr ' ' '=')"
  fi
  if ! DECODED=$(printf '%s' "$KEY" | base64 -d 2>/tmp/setllmkey-b64.err); then
    echo "ERROR: base64 decode failed — use setllmkey --hex instead." >&2
    head -c 120 /tmp/setllmkey-b64.err 2>/dev/null || true
    echo >&2
    exit 1
  fi
  KEY=$(printf '%s' "$DECODED" | tr -d '\r\n')
else
  KEY=${KEY//ß/-}
  KEY=${KEY//ÃŸ/-}
fi

if [[ -z "$KEY" ]]; then
  echo "Empty key after decode — aborted." >&2
  exit 1
fi

if [[ "$KEY" == sk-ant-oat* ]]; then
  echo "ERROR: sk-ant-oat is an OAuth/setup token, not a Console API key." >&2
  exit 1
fi

if [[ "$KEY" != sk-ant-usr* && "$KEY" != sk-ant-api* && "$KEY" != sk-ant-* ]]; then
  echo "ERROR: Key should start with sk-ant-usr or sk-ant-api (got prefix: ${KEY:0:14}… len=${#KEY})" >&2
  exit 1
fi

echo "Accepted prefix ${KEY:0:12}… len=${#KEY}"

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

python3 - <<'PY'
import json, urllib.request, urllib.error
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
    print("API_PROBE_FAIL", e.code, e.read()[:220].decode(errors="replace"))
    print("HINT: Create a NEW key, encode with --hex on your PC, retry setllmkey --hex")
    raise SystemExit(2)
PY

curl -sS http://127.0.0.1:8088/health | python3 -c 'import sys,json;d=json.load(sys.stdin);print("llmConfigured=",d.get("llmConfigured"));print("llmKeyStatus=",d.get("llmKeyStatus"));print("llmProvider=",d.get("llmProvider"))'
echo "Done. Do not paste the key into chat."
