#!/usr/bin/env bash
# Wrapper called by the ScooterCheck worker after an app upload:
#   decrypt-firm.sh <input.enc> <output.bin>
#
# Assumes ninebottea (or equivalent) is ALREADY installed on this host.
# Put keys only in /etc/scootercheck/decrypt.env (chmod 600) — never in git.
set -euo pipefail

IN="${1:?usage: decrypt-firm.sh input.enc output.bin}"
OUT="${2:?usage: decrypt-firm.sh input.enc output.bin}"

if [[ ! -f "$IN" ]]; then
  echo "input missing: $IN" >&2
  exit 2
fi

# Optional vault/env with KEY / NINEBOTTEA_BIN — create on the Hetzner host.
if [[ -f /etc/scootercheck/decrypt.env ]]; then
  # shellcheck disable=SC1091
  source /etc/scootercheck/decrypt.env
fi

BIN="${NINEBOTTEA_BIN:-ninebottea}"
if ! command -v "$BIN" >/dev/null 2>&1 && [[ ! -x "$BIN" ]]; then
  echo "ninebottea not found (NINEBOTTEA_BIN=$BIN). Install it on the server first." >&2
  exit 3
fi

mkdir -p "$(dirname "$OUT")"

# --- Adjust this ONE line to match YOUR installed CLI ---
# Common pattern: binary + subcommand + in + out (change if your tool differs).
# Keys must already be available to the tool via decrypt.env / its own config.
"$BIN" decrypt "$IN" "$OUT"

if [[ ! -s "$OUT" ]]; then
  echo "decrypt produced empty output: $OUT" >&2
  exit 4
fi

echo "decrypted $(wc -c < "$OUT") bytes -> $OUT"
