#!/usr/bin/env bash
# ONE-TIME host bootstrap for least-privilege SSH deploy user `scootercheck-deploy`.
#
# Document + run ON the Hetzner VPS as root (Hetzner Console / break-glass).
# Default: DRY-RUN (safe/idempotent preview). Live: CONFIRM_BOOTSTRAP=YES
#
# Creates / ensures:
#   - system user scootercheck-deploy with ~/.ssh/authorized_keys
#   - write access to /opt/scootercheck/releases (+ parent for symlink replace)
#   - sudoers limited to systemctl restart/status/is-active scootercheck-fw
#   - flock lock path writable
#
# Does NOT:
#   - deploy application code
#   - read or rewrite /etc/scootercheck/*.env
#   - grant root shell / ALL=(ALL)
#   - disable host-key checking (client-side)
#
# Migration from root@ (phase1-rollout.sh historical default):
#   1) Generate deploy keypair offline; put public key in DEPLOY_PUBKEY_FILE
#   2) CONFIRM_BOOTSTRAP=YES DEPLOY_PUBKEY_FILE=… ./bootstrap-deploy-user.sh
#   3) Set GitHub Environment secrets:
#        HETZNER_SSH_USER=scootercheck-deploy
#        HETZNER_SSH_PRIVATE_KEY=<matching private key>
#        HETZNER_SSH_KNOWN_HOSTS=<ssh-keyscan -H api.tuningscanner.de>
#        HETZNER_SSH_HOST=api.tuningscanner.de
#   4) Keep root key offline; prefer deploy user for all CD
set -euo pipefail

CONFIRM_BOOTSTRAP="${CONFIRM_BOOTSTRAP:-NO}"
DEPLOY_USER="${DEPLOY_USER:-scootercheck-deploy}"
DEPLOY_GROUP="${DEPLOY_GROUP:-$DEPLOY_USER}"
APP_OWNER="${APP_OWNER:-scootercheck}"
DEPLOY_PUBKEY_FILE="${DEPLOY_PUBKEY_FILE:-}"
DEPLOY_PUBKEY="${DEPLOY_PUBKEY:-}"
RELEASES_ROOT="${RELEASES_ROOT:-/opt/scootercheck/releases}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/scootercheck}"
APP_LINK="${APP_LINK:-/opt/scootercheck/firmware-analysis}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
SUDOERS_FILE="${SUDOERS_FILE:-/etc/sudoers.d/scootercheck-deploy}"
LOCK_FILE="${LOCK_FILE:-/var/lock/scootercheck-fw-deploy.lock}"

log() { printf '[bootstrap-deploy-user] %s\n' "$*" >&2; }
die() { printf '[bootstrap-deploy-user] ERROR: %s\n' "$*" >&2; exit 1; }

plan() {
  cat <<EOF
Would (idempotent):
  1) useradd --system --create-home --shell /bin/bash $DEPLOY_USER (if missing)
  2) install authorized_keys from DEPLOY_PUBKEY_FILE or DEPLOY_PUBKEY
  3) mkdir -p $RELEASES_ROOT; chown $DEPLOY_USER for releases tree
  4) group-write on $DEPLOY_ROOT so symlink $APP_LINK can be replaced
  5) sudoers ($SUDOERS_FILE): NOPASSWD systemctl restart|start|stop|status|is-active[--quiet] $SERVICE_NAME (/bin + /usr/bin)
  6) ensure lock file $LOCK_FILE writable by $DEPLOY_USER
  7) NOT grant root shell; NOT read /etc/scootercheck secrets
  8) NOT touch /var/lib/scootercheck data

Migration: stop using root@ for Actions; set HETZNER_SSH_USER=$DEPLOY_USER
EOF
}

plan
if [[ "$CONFIRM_BOOTSTRAP" != "YES" ]]; then
  log "DRY-RUN (set CONFIRM_BOOTSTRAP=YES to apply)"
  exit 0
fi

[[ "$(id -u)" -eq 0 ]] || die "must run as root for live bootstrap"

PUBKEY_CONTENT=""
if [[ -n "$DEPLOY_PUBKEY" ]]; then
  PUBKEY_CONTENT="$DEPLOY_PUBKEY"
elif [[ -n "$DEPLOY_PUBKEY_FILE" && -f "$DEPLOY_PUBKEY_FILE" ]]; then
  PUBKEY_CONTENT="$(tr -d '\r' <"$DEPLOY_PUBKEY_FILE" | head -1)"
else
  die "DEPLOY_PUBKEY_FILE or DEPLOY_PUBKEY required for live bootstrap"
fi
case "$PUBKEY_CONTENT" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*) ;;
  *) die "public key does not look like OpenSSH format" ;;
esac

id "$DEPLOY_USER" &>/dev/null || useradd --system --create-home --shell /bin/bash --user-group "$DEPLOY_USER"

HOME_DIR="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_GROUP" "$HOME_DIR/.ssh"
AUTH="$HOME_DIR/.ssh/authorized_keys"
touch "$AUTH"
chmod 600 "$AUTH"
chown "$DEPLOY_USER:$DEPLOY_GROUP" "$AUTH"
if grep -Fqx "$PUBKEY_CONTENT" "$AUTH" 2>/dev/null; then
  log "pubkey already present in authorized_keys"
else
  printf '%s\n' "$PUBKEY_CONTENT" >>"$AUTH"
  log "pubkey appended to authorized_keys"
fi

mkdir -p "$RELEASES_ROOT" "$DEPLOY_ROOT"
chown -R "$DEPLOY_USER:$DEPLOY_GROUP" "$RELEASES_ROOT"
chmod 755 "$DEPLOY_ROOT"
chmod 775 "$RELEASES_ROOT"
# Parent must allow deploy user to replace the current symlink
chgrp "$DEPLOY_GROUP" "$DEPLOY_ROOT"
chmod 775 "$DEPLOY_ROOT"

touch "$LOCK_FILE"
chown "$DEPLOY_USER:$DEPLOY_GROUP" "$LOCK_FILE"
chmod 664 "$LOCK_FILE"

# Keep runtime ownership of current tree if it already exists as a directory
if [[ -e "$APP_LINK" || -L "$APP_LINK" ]]; then
  if id "$APP_OWNER" &>/dev/null; then
    chown -h "$APP_OWNER:$APP_OWNER" "$APP_LINK" 2>/dev/null || true
  fi
fi

# Cycle 13: whitelist both /bin and /usr/bin (Ubuntu usrmerge) and is-active --quiet
# (release-deploy.sh uses `systemctl is-active --quiet`; bare is-active alone fails sudo).
cat >"$SUDOERS_FILE" <<EOF
# Managed by ScooterCheck bootstrap-deploy-user.sh — least privilege
# Do not grant ALL=(ALL) ALL
Cmnd_Alias SCOOTERCHECK_FW_CTL = \\
  /bin/systemctl restart ${SERVICE_NAME}, /bin/systemctl restart ${SERVICE_NAME}.service, \\
  /usr/bin/systemctl restart ${SERVICE_NAME}, /usr/bin/systemctl restart ${SERVICE_NAME}.service, \\
  /bin/systemctl start ${SERVICE_NAME}, /bin/systemctl start ${SERVICE_NAME}.service, \\
  /usr/bin/systemctl start ${SERVICE_NAME}, /usr/bin/systemctl start ${SERVICE_NAME}.service, \\
  /bin/systemctl stop ${SERVICE_NAME}, /bin/systemctl stop ${SERVICE_NAME}.service, \\
  /usr/bin/systemctl stop ${SERVICE_NAME}, /usr/bin/systemctl stop ${SERVICE_NAME}.service, \\
  /bin/systemctl status ${SERVICE_NAME}, /bin/systemctl status ${SERVICE_NAME}.service, \\
  /usr/bin/systemctl status ${SERVICE_NAME}, /usr/bin/systemctl status ${SERVICE_NAME}.service, \\
  /bin/systemctl is-active ${SERVICE_NAME}, /bin/systemctl is-active ${SERVICE_NAME}.service, \\
  /usr/bin/systemctl is-active ${SERVICE_NAME}, /usr/bin/systemctl is-active ${SERVICE_NAME}.service, \\
  /bin/systemctl is-active --quiet ${SERVICE_NAME}, /bin/systemctl is-active --quiet ${SERVICE_NAME}.service, \\
  /usr/bin/systemctl is-active --quiet ${SERVICE_NAME}, /usr/bin/systemctl is-active --quiet ${SERVICE_NAME}.service
${DEPLOY_USER} ALL=(root) NOPASSWD: SCOOTERCHECK_FW_CTL
EOF
chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE" || die "visudo validation failed — fix $SUDOERS_FILE"

log "Bootstrap applied for $DEPLOY_USER"
log "Next: set GitHub Environment production secrets (HETZNER_SSH_USER=$DEPLOY_USER, known_hosts, …)"
log "See docs/HETZNER_DEPLOYMENT_SETUP.md"
