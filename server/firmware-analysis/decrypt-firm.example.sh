#!/usr/bin/env bash
# Example wrapper — replace the body with a call to YOUR already-installed decrypt tool.
# Usage: decrypt-firm.sh <input.enc> <output.bin>
#
# Do NOT commit real keys. Load them from a vault/env inside this script on the server.
set -euo pipefail

IN="${1:?input.enc}"
OUT="${2:?output.bin}"

if [[ ! -f "$IN" ]]; then
  echo "input missing: $IN" >&2
  exit 2
fi

# --- REPLACE THIS BLOCK with your installed tool invocation ---
# Example shape only (placeholders):
#   source /etc/scootercheck/decrypt.env   # KEY=... from vault
#   /opt/your-tool/decrypt --in "$IN" --out "$OUT"
#
# For smoke tests without decrypt: refuse encrypted input.
echo "DECRYPT_CMD not configured: edit decrypt-firm.example.sh to call your installed tool" >&2
exit 3
