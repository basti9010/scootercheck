#!/usr/bin/env bash
# Flip versioned release into place. Run ON the Hetzner host (Actions rsyncs first).
#
# Layout (existing stack — not a second architecture):
#   /opt/scootercheck/releases/<sha>/     versioned app tree
#   /opt/scootercheck/firmware-analysis → symlink to current release
#   /var/lib/scootercheck                 data (NEVER wiped)
#   /etc/scootercheck/*.env               secrets (NEVER overwritten)
#
# Required: CONFIRM_PROD_DEPLOY=YES DEPLOY_SHA=<fullsha>
# Optional: REMOTE_APP, RELEASES_ROOT, REBUILD_VENV=1, HEALTH_URL, KEEP_RELEASES
# Mutex: flock on /var/lock/scootercheck-fw-deploy.lock (or LOCK_FILE)
set -euo pipefail

CONFIRM_PROD_DEPLOY="${CONFIRM_PROD_DEPLOY:-NO}"
DEPLOY_SHA="${DEPLOY_SHA:-}"
RELEASES_ROOT="${RELEASES_ROOT:-/opt/scootercheck/releases}"
REMOTE_APP="${REMOTE_APP:-/opt/scootercheck/firmware-analysis}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
LOCK_FILE="${LOCK_FILE:-/var/lock/scootercheck-fw-deploy.lock}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8088/health}"
REBUILD_VENV="${REBUILD_VENV:-0}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
APP_OWNER="${APP_OWNER:-scootercheck}"

log() { printf '[release-deploy] %s\n' "$*" >&2; }
die() { printf '[release-deploy] ERROR: %s\n' "$*" >&2; exit 1; }

sysctl_cmd() {
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl "$@"
  else
    sudo -n systemctl "$@"
  fi
}

[[ "$CONFIRM_PROD_DEPLOY" == "YES" ]] || die "Refusing: set CONFIRM_PROD_DEPLOY=YES"
[[ -n "$DEPLOY_SHA" ]] || die "DEPLOY_SHA required"
[[ "$DEPLOY_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || die "DEPLOY_SHA must be a full 40-char git SHA"
DEPLOY_SHA="$(printf '%s' "$DEPLOY_SHA" | tr 'A-F' 'a-f')"
RELEASE_DIR="$RELEASES_ROOT/$DEPLOY_SHA"
[[ -d "$RELEASE_DIR" ]] || die "Missing release tree $RELEASE_DIR"
[[ -f "$RELEASE_DIR/app.py" ]] || die "Release missing app.py"
# Never ship secrets into the release tree via this flip.
[[ ! -e "$RELEASE_DIR/firmware-analysis.env" ]] || die "Refusing: env file inside release tree"
[[ ! -e /var/lib/scootercheck/app.py ]] || die "Unexpected app.py under /var/lib/scootercheck"

# flock mutex — wait up to 10 minutes for concurrent CD/ops
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -w 600 9; then
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

prepare_venv() {
  if [[ -d "$RELEASE_DIR/.venv/bin" && -x "$RELEASE_DIR/.venv/bin/python" && "$REBUILD_VENV" != "1" ]]; then
    log "venv already present under release"
    return 0
  fi
  if [[ "$REBUILD_VENV" != "1" && -n "$PREV" && -d "$PREV/.venv" ]]; then
    log "Copying .venv from previous release (preserve path)"
    rm -rf "$RELEASE_DIR/.venv"
    cp -a "$PREV/.venv" "$RELEASE_DIR/.venv"
    return 0
  fi
  log "Building .venv from requirements.txt"
  local py
  if [[ -x /usr/bin/python3.12 ]]; then
    py=/usr/bin/python3.12
  else
    py=python3
  fi
  rm -rf "$RELEASE_DIR/.venv"
  "$py" -m venv "$RELEASE_DIR/.venv"
  "$RELEASE_DIR/.venv/bin/pip" install -U pip
  "$RELEASE_DIR/.venv/bin/pip" install -r "$RELEASE_DIR/requirements.txt"
}

prepare_venv
[[ -x "$RELEASE_DIR/.venv/bin/python" ]] || die "venv python missing after prepare"

# Record previous pointer for rollback
mkdir -p "$RELEASES_ROOT"
if [[ -n "$PREV" ]]; then
  printf '%s\n' "$PREV" >"$RELEASES_ROOT/previous"
fi
printf '%s\n' "$RELEASE_DIR" >"$RELEASES_ROOT/current_target"
printf '%s\n' "$DEPLOY_SHA" >"$RELEASE_DIR/.release-sha"

# Atomic-ish symlink swap
TMP_LINK="${REMOTE_APP}.new"
ln -sfn "$RELEASE_DIR" "$TMP_LINK"
mv -Tf "$TMP_LINK" "$REMOTE_APP"

# Ensure runtime user can read release
if id "$APP_OWNER" &>/dev/null; then
  chown -R "$APP_OWNER:$APP_OWNER" "$RELEASE_DIR" || true
  chown -h "$APP_OWNER:$APP_OWNER" "$REMOTE_APP" 2>/dev/null || true
fi

# Restart unit (deploy user needs limited sudo — see bootstrap-deploy-user.sh).
# sleep ≥3s: uvicorn bind lags; Cycle 13 live deploy saw curl fail at t=0 after restart.
sysctl_cmd restart "$SERVICE_NAME"
sleep 3
sysctl_cmd is-active --quiet "$SERVICE_NAME" || die "service not active after restart"

BODY="$(curl -fsS --max-time 15 "$HEALTH_URL")" \
  || die "healthcheck failed after deploy ($HEALTH_URL)"
printf '%s' "$BODY" | grep -q '"ok"[[:space:]]*:[[:space:]]*true' \
  || die "health payload missing ok=true"

# Prune old SHA dirs (keep N + current + previous)
prune() {
  local cur prev count d abs
  cur=$(readlink -f "$REMOTE_APP" 2>/dev/null || true)
  prev=$(cat "$RELEASES_ROOT/previous" 2>/dev/null || true)
  count=0
  # shellcheck disable=SC2012
  for d in $(ls -1dt "$RELEASES_ROOT"/*/ 2>/dev/null | sed 's:/$::'); do
    abs="$d"
    base=$(basename "$abs")
    [[ "$base" =~ ^[0-9a-f]{40}$ || "$base" =~ ^pre-cd- || "$base" =~ ^legacy- ]] || continue
    if [[ "$abs" == "$cur" || "$abs" == "$prev" ]]; then
      continue
    fi
    count=$((count + 1))
    if [[ "$count" -gt "$KEEP_RELEASES" ]]; then
      rm -rf -- "$abs"
      log "pruned $base"
    fi
  done
}
prune || log "WARN: prune failed (non-fatal)"

log "DEPLOYED sha=$DEPLOY_SHA path=$RELEASE_DIR"
log "Data dirs untouched under /var/lib/scootercheck"
log "Secrets untouched under /etc/scootercheck"
echo "ok sha=$DEPLOY_SHA"
