#!/usr/bin/env bash
# ONE-TIME host bootstrap for least-privilege deploy user.
# Default: DRY-RUN. Live: CONFIRM_BOOTSTRAP=YES
set -euo pipefail

CONFIRM_BOOTSTRAP="${CONFIRM_BOOTSTRAP:-NO}"
DEPLOY_USER="${DEPLOY_USER:-scootercheck-deploy}"
DEPLOY_PUBKEY_FILE="${DEPLOY_PUBKEY_FILE:-}"
RELEASES_ROOT="${RELEASES_ROOT:-/opt/scootercheck/releases}"
APP_LINK="${APP_LINK:-/opt/scootercheck/firmware-analysis}"

log() { printf '[bootstrap-deploy-user] %s\n' "$*" >&2; }

plan() {
  cat <<EOF
Would:
  1) useradd --system --create-home $DEPLOY_USER (if missing)
  2) install authorized_keys from DEPLOY_PUBKEY_FILE
  3) mkdir -p $RELEASES_ROOT; chown $DEPLOY_USER for releases tree
  4) sudoers: $DEPLOY_USER ALL=(root) NOPASSWD: /bin/systemctl restart scootercheck-fw, /bin/systemctl status scootercheck-fw, /bin/systemctl is-active scootercheck-fw
  5) NOT grant root shell; NOT read /etc/scootercheck secrets by default
EOF
}

plan
if [[ "$CONFIRM_BOOTSTRAP" != "YES" ]]; then
  log "DRY-RUN (set CONFIRM_BOOTSTRAP=YES to apply)"
  exit 0
fi

[[ "$(id -u)" -eq 0 ]] || { log "ERROR: must run as root for live bootstrap"; exit 1; }
[[ -n "$DEPLOY_PUBKEY_FILE" && -f "$DEPLOY_PUBKEY_FILE" ]] || { log "ERROR: DEPLOY_PUBKEY_FILE required"; exit 1; }

id "$DEPLOY_USER" &>/dev/null || useradd --system --create-home --shell /bin/bash "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$DEPLOY_PUBKEY_FILE" "/home/$DEPLOY_USER/.ssh/authorized_keys"
mkdir -p "$RELEASES_ROOT"
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$RELEASES_ROOT"
# Ensure parent exists for symlink swaps
mkdir -p "$(dirname "$APP_LINK")"

SUDOERS=/etc/sudoers.d/scootercheck-deploy
cat >"$SUDOERS" <<EOF
# Managed by ScooterCheck bootstrap-deploy-user.sh — least privilege
$DEPLOY_USER ALL=(root) NOPASSWD: /bin/systemctl restart scootercheck-fw, /bin/systemctl status scootercheck-fw, /bin/systemctl is-active scootercheck-fw, /bin/systemctl restart scootercheck-fw.service, /bin/systemctl status scootercheck-fw.service, /bin/systemctl is-active scootercheck-fw.service
EOF
chmod 440 "$SUDOERS"
visudo -cf "$SUDOERS"
log "Bootstrap applied for $DEPLOY_USER"
