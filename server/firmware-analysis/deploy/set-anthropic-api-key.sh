#!/usr/bin/env bash
# Set a Claude Console API key into firmware-analysis.env without echoing it.
# Usage:
#   setllmkey           # raw key via SSH from PC
#   setllmkey --hex     # two short hex parts (Hetzner web console)
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

read_one_hidden() {
  local line
  IFS= read -r -s line || true
  line=${line%$'\r'}
  # strip spaces
  printf '%s' "${line// /}"
}

case "$MODE" in
  hex)
    cat <<'EOF'
Hetzner console truncates long pastes — we need TWO short hex parts.

On Windows PowerShell (only these lines, no prompt):

  $h=([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes('sk-ant-usr-DEIN_KEY'))).Replace('-','').ToLower()
  $h.Length
  $h.Substring(0, [Math]::Min(100, $h.Length))
  if ($h.Length -gt 100) { $h.Substring(100) }

Length must be ~212. Copy line "Part A" (first ~100), then "Part B" (rest).
EOF
    echo
    echo -n "Paste HEX part 1, Enter: "
    PART1=$(read_one_hidden)
    echo
    echo -n "Paste HEX part 2, Enter: "
    PART2=$(read_one_hidden)
    echo
    KEY="${PART1}${PART2}"
    KEY=$(printf '%s' "$KEY" | tr 'A-F' 'a-f' | tr -d '\r\n \t')
    echo "hex_len=${#KEY} (part1=${#PART1} part2=${#PART2}; expect ~212)"
    if [[ ! "$KEY" =~ ^[0-9a-f]+$ ]]; then
      echo "ERROR: not hex (only 0-9 a-f). Check you copied PowerShell hex, not the key." >&2
      exit 1
    fi
    if (( ${#KEY} % 2 == 1 )); then
      echo "ERROR: hex length odd (${#KEY}) — a character is missing in part1 or part2." >&2
      exit 1
    fi
    if (( ${#KEY} < 190 )); then
      echo "ERROR: hex too short (${#KEY}). Full key hex is ~212. Re-copy BOTH parts from PowerShell." >&2
      exit 1
    fi
    if ! KEY=$(printf '%s' "$KEY" | xxd -r -p 2>/dev/null | tr -d '\r\n'); then
      echo "ERROR: hex decode failed." >&2
      exit 1
    fi
    ;;
  b64)
    echo "Paste BASE64, Enter. Prefer setllmkey --hex"
    KEY=$(read_one_hidden)
    echo
    KEY=$(printf '%s' "$KEY" | tr -d '\r\n \t')
    pad=$(( (4 - ${#KEY} % 4) % 4 ))
    if (( pad > 0 )); then KEY="${KEY}$(printf '%*s' "$pad" '' | tr ' ' '=')"; fi
    if ! KEY=$(printf '%s' "$KEY" | base64 -d 2>/dev/null | tr -d '\r\n'); then
      echo "ERROR: base64 decode failed — use setllmkey --hex" >&2
      exit 1
    fi
    ;;
  *)
    echo "Paste Claude API key, Enter. (Hetzner web: use setllmkey --hex)"
    KEY=$(read_one_hidden)
    echo
    KEY=${KEY//ß/-}
    KEY=${KEY//ÃŸ/-}
    KEY=$(printf '%s' "$KEY" | tr -d '\r\n \t')
    ;;
esac

if [[ -z "$KEY" ]]; then
  echo "Empty key — aborted." >&2
  exit 1
fi

if [[ "$KEY" == sk-ant-oat* ]]; then
  echo "ERROR: sk-ant-oat is OAuth, not an API key." >&2
  exit 1
fi

if [[ "$KEY" != sk-ant-usr* && "$KEY" != sk-ant-api* && "$KEY" != sk-ant-* ]]; then
  echo "ERROR: expected sk-ant-usr/sk-ant-api prefix (got ${KEY:0:14}… len=${#KEY})" >&2
  exit 1
fi

if (( ${#KEY} < 100 )); then
  echo "ERROR: key too short (len=${#KEY}). Need full key ~106 chars." >&2
  exit 1
fi

if [[ "$KEY" != *AA ]]; then
  echo "WARN: key does not end with AA — may still be truncated."
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
awk '/^LLM_MODEL=/ { if (++m>1) next } { print }' "$tmp" >"${tmp}.2"
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
        key=line.split("=",1)[1].strip().replace("ß","-")
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
    raise SystemExit(2)
PY

curl -sS http://127.0.0.1:8088/health | python3 -c 'import sys,json;d=json.load(sys.stdin);print("llmConfigured=",d.get("llmConfigured"));print("llmKeyStatus=",d.get("llmKeyStatus"))'
echo "Done. Do not paste the key into chat."
