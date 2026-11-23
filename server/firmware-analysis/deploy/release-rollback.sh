#!/usr/bin/env bash
# Restore previous (or explicit) release symlink, restart systemd, health-check.
# Does not undo /var/lib/scootercheck data or /etc/scootercheck secrets.
#
# Required: CONFIRM_PROD_DEPLOY=YES
# Optional: ROLLBACK_SHA=<40-char>  (otherwise uses releases/previous)
set -euo pipefail

CONFIRM_PROD_DEPLOY="${CONFIRM_PROD_DEPLOY:-NO}"
RELEASES_ROOT="${RELEASES_ROOT:-/opt/scootercheck/releases}"
REMOTE_APP="${REMOTE_APP:-/opt/scootercheck/firmware-analysis}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
LOCK_FILE="${LOCK_FILE:-/var/lock/scootercheck-fw-deploy.lock}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8088/health}"
ROLLBACK_SHA="${ROLLBACK_SHA:-}"
APP_OWNER="${APP_OWNER:-scootercheck}"

log() { printf '[release-rollback] %s\n' "$*" >&2; }
die() { printf '[release-rollback] ERROR: %s\n' "$*" >&2; exit 1; }

sysctl_cmd() {
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl "$@"
  else
    sudo -n systemctl "$@"
  fi
}

[[ "$CONFIRM_PROD_DEPLOY" == "YES" ]] || die "Refusing: set CONFIRM_PROD_DEPLOY=YES"

if [[ -n "$ROLLBACK_SHA" ]]; then
  [[ "$ROLLBACK_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || die "ROLLBACK_SHA must be a full 40-char SHA"
  ROLLBACK_SHA="$(printf '%s' "$ROLLBACK_SHA" | tr 'A-F' 'a-f')"
  PREV="$RELEASES_ROOT/$ROLLBACK_SHA"
else
  [[ -f "$RELEASES_ROOT/previous" ]] || die "No previous release recorded at $RELEASES_ROOT/previous"
  PREV=$(tr -d '\r' <"$RELEASES_ROOT/previous" | tail -1)
fi
[[ -d "$PREV" ]] || die "Previous path missing: $PREV"
[[ -f "$PREV/app.py" ]] || die "Previous release incomplete: $PREV"

mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
flock -w 600 9 || die "Deploy lock held"

# Save current as previous for possible re-flip
if [[ -L "$REMOTE_APP" ]]; then
  CUR=$(readlink -f "$REMOTE_APP" || true)
  [[ -n "$CUR" ]] && printf '%s\n' "$CUR" >"$RELEASES_ROOT/previous"
fi

TMP_LINK="${REMOTE_APP}.new"
ln -sfn "$PREV" "$TMP_LINK"
mv -Tf "$TMP_LINK" "$REMOTE_APP"
printf '%s\n' "$PREV" >"$RELEASES_ROOT/current_target"

if id "$APP_OWNER" &>/dev/null; then
  chown -h "$APP_OWNER:$APP_OWNER" "$REMOTE_APP" 2>/dev/null || true
fi

sysctl_cmd restart "$SERVICE_NAME"
sleep 2
sysctl_cmd is-active --quiet "$SERVICE_NAME" || die "service not active after rollback"

BODY="$(curl -fsS --max-time 15 "$HEALTH_URL")" \
  || die "healthcheck failed after rollback ($HEALTH_URL)"
printf '%s' "$BODY" | grep -q '"ok"[[:space:]]*:[[:space:]]*true' \
  || die "health payload missing ok=true after rollback"

log "Rolled back to $PREV"
echo "ok rollback=$PREV"
