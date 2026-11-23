#!/usr/bin/env bash
# Flip versioned release into place. Run ON the Hetzner host (or via Actions SSH).
# Never deletes /var/lib/scootercheck. Never overwrites /etc/scootercheck/*.env.
#
# Required: CONFIRM_PROD_DEPLOY=YES DEPLOY_SHA=<fullsha>
# Optional: REMOTE_APP=/opt/scootercheck/firmware-analysis
#           RELEASES_ROOT=/opt/scootercheck/releases
set -euo pipefail

CONFIRM_PROD_DEPLOY="${CONFIRM_PROD_DEPLOY:-NO}"
DEPLOY_SHA="${DEPLOY_SHA:-}"
RELEASES_ROOT="${RELEASES_ROOT:-/opt/scootercheck/releases}"
REMOTE_APP="${REMOTE_APP:-/opt/scootercheck/firmware-analysis}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
LOCK_FILE="${LOCK_FILE:-/var/lock/scootercheck-fw-deploy.lock}"

log() { printf '[release-deploy] %s\n' "$*" >&2; }
die() { printf '[release-deploy] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$CONFIRM_PROD_DEPLOY" == "YES" ]] || die "Refusing: set CONFIRM_PROD_DEPLOY=YES"
[[ -n "$DEPLOY_SHA" ]] || die "DEPLOY_SHA required"
[[ "$DEPLOY_SHA" =~ ^[0-9a-fA-F]{7,40}$ ]] || die "DEPLOY_SHA must be a git SHA"
RELEASE_DIR="$RELEASES_ROOT/$DEPLOY_SHA"
[[ -d "$RELEASE_DIR" ]] || die "Missing release tree $RELEASE_DIR"
[[ -f "$RELEASE_DIR/app.py" ]] || die "Release missing app.py"

# flock mutex — prevent concurrent flips
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  die "Another deploy holds $LOCK_FILE"
fi

PREV=""
if [[ -L "$REMOTE_APP" ]]; then
  PREV=$(readlink -f "$REMOTE_APP" || true)
elif [[ -d "$REMOTE_APP" && ! -L "$REMOTE_APP" ]]; then
  # First migration: keep existing tree as releases/pre-cd-<timestamp>
  MIG="pre-cd-$(date -u +%Y%m%dT%H%M%SZ)"
  log "Migrating non-symlink $REMOTE_APP → $RELEASES_ROOT/$MIG"
  mkdir -p "$RELEASES_ROOT"
  mv "$REMOTE_APP" "$RELEASES_ROOT/$MIG"
  PREV="$RELEASES_ROOT/$MIG"
fi

# Preserve venv from previous release when present
if [[ -n "$PREV" && -d "$PREV/.venv" && ! -d "$RELEASE_DIR/.venv" ]]; then
  log "Copying .venv from previous release (fast path)"
  cp -a "$PREV/.venv" "$RELEASE_DIR/.venv"
fi

# Record previous pointer for rollback
mkdir -p "$RELEASES_ROOT"
if [[ -n "$PREV" ]]; then
  echo "$PREV" >"$RELEASES_ROOT/previous"
fi
echo "$RELEASE_DIR" >"$RELEASES_ROOT/current_target"

# Atomic-ish symlink swap
TMP_LINK="${REMOTE_APP}.new"
ln -sfn "$RELEASE_DIR" "$TMP_LINK"
mv -Tf "$TMP_LINK" "$REMOTE_APP"

# Ensure scootercheck can read release
if id scootercheck &>/dev/null; then
  chown -R scootercheck:scootercheck "$RELEASE_DIR" || true
fi

# Restart unit (deploy user needs limited sudo)
if command -v systemctl >/dev/null; then
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl restart "$SERVICE_NAME"
  else
    sudo -n systemctl restart "$SERVICE_NAME"
  fi
fi

log "DEPLOYED sha=$DEPLOY_SHA path=$RELEASE_DIR"
log "Data dirs untouched under /var/lib/scootercheck"
log "Secrets untouched under /etc/scootercheck"
echo "ok sha=$DEPLOY_SHA"
