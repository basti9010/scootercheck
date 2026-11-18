#!/usr/bin/env bash
# Wrapper: decrypt-firm.sh <input.enc> <output.bin>
# Tries tea then xtea unless VARIANT is fixed in decrypt.env.
set -euo pipefail

IN="${1:?usage: decrypt-firm.sh input.enc output.bin}"
OUT="${2:?usage: decrypt-firm.sh input.enc output.bin}"

if [[ ! -f "$IN" ]]; then
  echo "input missing: $IN" >&2
  exit 2
fi

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

run_one() {
  local variant="$1"
  local tmp="${OUT}.trying"
  local args=(decrypt "$IN" "$tmp")
  if [[ -n "${KEY:-}" ]]; then
    args+=(--key "$KEY")
  fi
  args+=(--variant "$variant")
  if "$BIN" "${args[@]}" 2>"${OUT}.err"; then
    if [[ -s "$tmp" ]]; then
      mv -f "$tmp" "$OUT"
      echo "decrypted $(wc -c < "$OUT") bytes via ${variant} -> $OUT"
      rm -f "${OUT}.err"
      return 0
    fi
  fi
  rm -f "$tmp"
  return 1
}

if [[ -n "${VARIANT:-}" ]]; then
  if run_one "$VARIANT"; then
    exit 0
  fi
  echo "decrypt failed (VARIANT=$VARIANT): $(cat "${OUT}.err" 2>/dev/null || true)" >&2
  exit 4
fi

# Auto: classic TEA first, then XTEA (newer firmware).
if run_one tea || run_one xtea; then
  exit 0
fi

echo "decrypt failed for tea and xtea: $(cat "${OUT}.err" 2>/dev/null || true)" >&2
exit 4
