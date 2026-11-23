#!/usr/bin/env bash
# Restore previous release symlink and restart. No DB/data undo.
set -euo pipefail

CONFIRM_PROD_DEPLOY="${CONFIRM_PROD_DEPLOY:-NO}"
RELEASES_ROOT="${RELEASES_ROOT:-/opt/scootercheck/releases}"
REMOTE_APP="${REMOTE_APP:-/opt/scootercheck/firmware-analysis}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
LOCK_FILE="${LOCK_FILE:-/var/lock/scootercheck-fw-deploy.lock}"

log() { printf '[release-rollback] %s\n' "$*" >&2; }
die() { printf '[release-rollback] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$CONFIRM_PROD_DEPLOY" == "YES" ]] || die "Refusing: set CONFIRM_PROD_DEPLOY=YES"
[[ -f "$RELEASES_ROOT/previous" ]] || die "No previous release recorded at $RELEASES_ROOT/previous"
PREV=$(cat "$RELEASES_ROOT/previous")
[[ -d "$PREV" ]] || die "Previous path missing: $PREV"

exec 9>"$LOCK_FILE"
flock -n 9 || die "Deploy lock held"

# Save current as previous for possible re-flip
if [[ -L "$REMOTE_APP" ]]; then
  CUR=$(readlink -f "$REMOTE_APP" || true)
  [[ -n "$CUR" ]] && echo "$CUR" >"$RELEASES_ROOT/previous"
fi

TMP_LINK="${REMOTE_APP}.new"
ln -sfn "$PREV" "$TMP_LINK"
mv -Tf "$TMP_LINK" "$REMOTE_APP"
echo "$PREV" >"$RELEASES_ROOT/current_target"

if command -v systemctl >/dev/null; then
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl restart "$SERVICE_NAME"
  else
    sudo -n systemctl restart "$SERVICE_NAME"
  fi
fi

log "Rolled back to $PREV"
echo "ok rollback=$PREV"
