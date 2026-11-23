#!/usr/bin/env bash
# Validate release config. Offline (CI): checks .env.example key coverage.
# On host: checks env file presence and path existence without printing secret values.
set -euo pipefail

MODE="${1:-offline}"  # offline | host
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_EXAMPLE="$APP_DIR/.env.example"
ENV_FILE="${ENV_FILE:-/etc/scootercheck/firmware-analysis.env}"

log() { printf '[validate-release-config] %s\n' "$*" >&2; }
die() { printf '[validate-release-config] ERROR: %s\n' "$*" >&2; exit 1; }

CRITICAL_KEYS=(
  API_TOKEN
  JWT_SECRET
  WORK_DIR
  HOST
  PORT
)

RECOMMENDED_KEYS=(
  DECRYPT_CMD
  PLAINTEXT_STORE
  DECOMPILE_STORE
  ENABLE_GHIDRA
  GHIDRA_HOME
  ADMIN_API_TOKEN
  API_TOKEN_GRANTS_ADMIN
)

offline_check() {
  [[ -f "$ENV_EXAMPLE" ]] || die "missing .env.example"
  local missing=0
  for k in "${CRITICAL_KEYS[@]}" "${RECOMMENDED_KEYS[@]}"; do
    if ! grep -qE "^#?${k}=" "$ENV_EXAMPLE" && ! grep -qE "^#?${k}=" "$ENV_EXAMPLE"; then
      # soft: .env.example may document differently
      if ! grep -q "$k" "$ENV_EXAMPLE"; then
        log "WARN: $k not mentioned in .env.example"
        missing=$((missing + 1))
      fi
    fi
  done
  [[ -f "$APP_DIR/app.py" ]] || die "app.py missing"
  [[ -f "$APP_DIR/deploy/scootercheck-fw.service" ]] || die "systemd unit missing in tree"
  [[ -f "$APP_DIR/deploy/deploy-manifest.txt" ]] || die "deploy-manifest.txt missing"
  log "offline validation OK (warnings=$missing)"
}

host_check() {
  [[ -f "$ENV_FILE" ]] || die "ENV_FILE missing: $ENV_FILE"
  for k in "${CRITICAL_KEYS[@]}"; do
    if ! grep -qE "^${k}=." "$ENV_FILE"; then
      die "critical key unset or empty: $k"
    fi
    log "key_present=$k"
  done
  # Values never printed
  if grep -qE '^API_TOKEN_GRANTS_ADMIN=1' "$ENV_FILE"; then
    log "WARN: API_TOKEN_GRANTS_ADMIN=1 — diagnostics require dedicated ADMIN_API_TOKEN; prefer 0"
  fi
  for p in /var/lib/scootercheck/firmware-jobs /var/lib/scootercheck/decrypted /var/lib/scootercheck/decompiled; do
    [[ -d "$p" ]] || log "WARN: data dir missing $p"
  done
  log "host validation OK (secret values not shown)"
}

case "$MODE" in
  offline) offline_check ;;
  host) host_check ;;
  *) die "usage: $0 [offline|host]" ;;
esac
