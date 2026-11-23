#!/usr/bin/env bash
# Validate firmware-analysis release/CD compatibility config (Cycle 12 Agent B).
#
# Modes:
#   offline (default)  CI-safe: .env.example completeness + deploy-manifest
#                      presence. Never reads host secrets or prints values.
#   host               On Hetzner: env *key names* present, path writability
#                      assumptions, systemd unit present. Never prints secret
#                      values — only key names and ok/missing.
#
# Usage: validate-release-config.sh [offline|host]
#        validate-release-config.sh [--offline|--host]
# Exit 0 on success, 1 on validation failure, 2 on usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="offline"
ENV_FILE_DEFAULT="/etc/scootercheck/firmware-analysis.env"
ENV_FILE="${FIRMWARE_ANALYSIS_ENV_FILE:-${ENV_FILE:-$ENV_FILE_DEFAULT}}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
MANIFEST="$SCRIPT_DIR/deploy-manifest.txt"
ENV_EXAMPLE="$APP_DIR/.env.example"
APP_PY="$APP_DIR/app.py"
REMOTE_APP="${FIRMWARE_ANALYSIS_APP_DIR:-/opt/scootercheck/firmware-analysis}"
RELEASES_ROOT="${RELEASES_ROOT:-/opt/scootercheck/releases}"

# Critical keys that must appear in .env.example (names only).
CRITICAL_ENV_KEYS=(
  API_TOKEN
  ADMIN_API_TOKEN
  API_TOKEN_GRANTS_ADMIN
  TRUST_API_TOKEN_CLIENT_ID
  JWT_SECRET
  JWT_ALGORITHM
  DECRYPT_CMD
  WORK_DIR
  PLAINTEXT_STORE
  DECOMPILE_STORE
  STOCK_FW_DIR
  GHIDRA_HOME
  ENABLE_GHIDRA
  HOST
  PORT
  ENABLE_ANGR
  ANGR_MAX_BYTES
  ANGR_TIMEOUT_SEC
  ANGR_MEM_MB
  ANGR_CFG_DEPTH
  ANGR_SYMBOLIC
)

# Host-mode keys that must be *set* (non-empty). Values never printed.
HOST_REQUIRED_KEYS=(
  API_TOKEN
  ADMIN_API_TOKEN
  JWT_SECRET
  DECRYPT_CMD
  WORK_DIR
  PLAINTEXT_STORE
  DECOMPILE_STORE
  STOCK_FW_DIR
  GHIDRA_HOME
)

HOST_WRITABLE_PATHS=(
  /var/lib/scootercheck/firmware-jobs
  /var/lib/scootercheck/decrypted
  /var/lib/scootercheck/decompiled
  /var/lib/scootercheck/stock-fw
)

HOST_OUTSIDE_RELEASE_PATHS=(
  /opt/ghidra
  /opt/scootercheck/decrypt-firm.sh
  /etc/scootercheck
)

usage() {
  cat <<'EOF'
Usage: validate-release-config.sh [offline|host]
       validate-release-config.sh [--offline|--host]

Never prints secret values. Safe for CI logs.
EOF
}

log() { printf '[validate-release] %s\n' "$*" >&2; }
fail() { printf '[validate-release] FAIL: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
ok() { printf '[validate-release] ok: %s\n' "$*" >&2; }

FAILURES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    offline|--offline) MODE=offline; shift ;;
    host|--host) MODE=host; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

env_example_mentions_key() {
  local key="$1" file="$2"
  grep -Eq "^[[:space:]]*#?[[:space:]]*${key}=" "$file"
}

env_file_has_nonempty_key() {
  local key="$1" file="$2"
  grep -Eq "^[[:space:]]*${key}=[^[:space:]#]+" "$file"
}

app_py_getenv_keys() {
  local file="$1"
  grep -oE 'os\.environ\.get\(\s*"[A-Z0-9_]+"' "$file" \
    | sed -E 's/.*"(.*)"/\1/' \
    | sort -u
}

manifest_entries() {
  local file="$1"
  grep -vE '^[[:space:]]*(#|$)' "$file" || true
}

validate_offline() {
  log "mode=offline app=$APP_DIR"

  [[ -f "$ENV_EXAMPLE" ]] || fail "missing .env.example"
  [[ -f "$MANIFEST" ]] || fail "missing deploy-manifest.txt"
  [[ -f "$APP_PY" ]] || fail "missing app.py"
  [[ -f "$SCRIPT_DIR/scootercheck-fw.service" ]] || fail "systemd unit missing in tree"
  [[ -f "$SCRIPT_DIR/RELEASE_COMPAT.md" ]] || fail "RELEASE_COMPAT.md missing"

  local key
  for key in "${CRITICAL_ENV_KEYS[@]}"; do
    if [[ -f "$ENV_EXAMPLE" ]] && env_example_mentions_key "$key" "$ENV_EXAMPLE"; then
      ok ".env.example mentions $key"
    else
      fail ".env.example missing critical key name: $key"
    fi
  done

  # Completeness: critical app.py getenv keys must be documented.
  local app_key
  if [[ -f "$APP_PY" ]]; then
    while IFS= read -r app_key; do
      [[ -n "$app_key" ]] || continue
      case "$app_key" in
        API_TOKEN|ADMIN_API_TOKEN|JWT_SECRET|JWT_ALGORITHM|DECRYPT_CMD|\
        WORK_DIR|PLAINTEXT_STORE|DECOMPILE_STORE|ENABLE_GHIDRA|\
        GHIDRA_PROCESSOR|GHIDRA_BASE_ADDR|JOB_RETENTION_DAYS|MAX_STORED_JOBS|\
        ANGR_TIMEOUT_SEC|ANGR_MEM_MB|ANGR_CFG_DEPTH|ANGR_SYMBOLIC)
          if env_example_mentions_key "$app_key" "$ENV_EXAMPLE"; then
            ok "app.py getenv $app_key documented in .env.example"
          else
            fail "app.py getenv $app_key not in .env.example"
          fi
          ;;
      esac
    done < <(app_py_getenv_keys "$APP_PY")
  fi

  local rel
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    if [[ -e "$APP_DIR/$rel" ]]; then
      ok "manifest path present: $rel"
    else
      fail "manifest path missing: $rel"
    fi
  done < <(manifest_entries "$MANIFEST")

  local diag
  for diag in diagnostics_models.py diagnostics_status.py diagnostics_tea.py \
              diagnostics_ghidra.py diagnostics_routes.py; do
    if grep -qxF "$diag" "$MANIFEST"; then
      ok "manifest lists C11 module $diag"
    else
      fail "manifest missing C11 module $diag"
    fi
  done

  if [[ "$FAILURES" -eq 0 ]]; then
    log "offline validation PASSED"
    return 0
  fi
  log "offline validation FAILED ($FAILURES)"
  return 1
}

validate_host() {
  log "mode=host (names only — no secret values)"

  if [[ ! -f "$ENV_FILE" ]]; then
    fail "EnvironmentFile missing (configured path)"
  else
    ok "EnvironmentFile present"
    local key
    for key in "${HOST_REQUIRED_KEYS[@]}"; do
      if env_file_has_nonempty_key "$key" "$ENV_FILE"; then
        ok "env key set: $key"
      else
        fail "env key missing or empty: $key"
      fi
    done
    for key in API_TOKEN_GRANTS_ADMIN TRUST_API_TOKEN_CLIENT_ID; do
      if grep -Eq "^[[:space:]]*${key}=" "$ENV_FILE"; then
        ok "env key present: $key"
      else
        fail "env key name absent: $key (expected explicit 0/1)"
      fi
    done
    if grep -qE '^[[:space:]]*API_TOKEN_GRANTS_ADMIN=1([[:space:]]|$)' "$ENV_FILE"; then
      fail "API_TOKEN_GRANTS_ADMIN=1 (must be 0 for CD-secure admin separation)"
    fi
  fi

  if [[ -f /etc/scootercheck/decrypt.env ]]; then
    ok "decrypt.env present (outside release; contents not printed)"
  else
    fail "decrypt.env missing at /etc/scootercheck/decrypt.env"
  fi

  local p
  for p in "${HOST_WRITABLE_PATHS[@]}"; do
    if [[ -d "$p" && -w "$p" ]]; then
      ok "writable data path: $p"
    elif [[ -d "$p" ]]; then
      fail "data path exists but not writable by current user: $p"
    else
      fail "data path missing: $p"
    fi
  done

  for p in "${HOST_OUTSIDE_RELEASE_PATHS[@]}"; do
    if [[ -e "$p" ]]; then
      ok "outside-release path exists: $p"
    else
      fail "outside-release path missing: $p"
    fi
  done

  if [[ -e "$REMOTE_APP" ]]; then
    ok "app dir present"
    if [[ -L "$REMOTE_APP" ]]; then
      ok "app dir is symlink (versioned release layout under $RELEASES_ROOT)"
    else
      log "note: app dir is not a symlink yet (pre-CD layout; release-deploy.sh migrates)"
    fi
    if [[ -x "$REMOTE_APP/.venv/bin/python" ]]; then
      ok "venv python present under app dir"
    else
      fail "venv python missing under app dir (.venv/bin/python)"
    fi
  else
    fail "app dir missing: $REMOTE_APP"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
      ok "systemd unit present: $SERVICE_NAME"
    else
      fail "systemd unit missing: $SERVICE_NAME"
    fi
  else
    fail "systemctl not available — cannot verify unit $SERVICE_NAME"
  fi

  local unit_src="$SCRIPT_DIR/scootercheck-fw.service"
  if [[ -f "$unit_src" ]]; then
    if grep -q 'ReadOnlyPaths=.*\/opt\/ghidra' "$unit_src"; then
      ok "unit lists /opt/ghidra in ReadOnlyPaths"
    else
      fail "unit missing /opt/ghidra ReadOnlyPaths"
    fi
    if grep -q 'ProtectHome=true' "$unit_src"; then
      ok "unit ProtectHome=true (NinebotTEA must live in venv, not /root)"
    else
      fail "unit missing ProtectHome=true"
    fi
  fi

  if [[ "$FAILURES" -eq 0 ]]; then
    log "host validation PASSED"
    return 0
  fi
  log "host validation FAILED ($FAILURES)"
  return 1
}

case "$MODE" in
  offline) validate_offline ;;
  host) validate_host ;;
  *) usage >&2; exit 2 ;;
esac
