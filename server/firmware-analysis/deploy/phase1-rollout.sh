#!/usr/bin/env bash
# Phase-1 firmware-analysis rollout to Hetzner.
#
# Default: DRY-RUN (no remote writes, no restart).
# Real deploy: CONFIRM_PROD_DEPLOY=YES ./deploy/phase1-rollout.sh
#
# Never deletes or modifies /var/lib/scootercheck (jobs, decrypted, stock-fw).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"                 # …/server/firmware-analysis
REPO_ROOT="$(cd "$APP_SRC/../.." && pwd)"               # repo root
REMOTE_HOST="${REMOTE_HOST:-root@api.tuningscanner.de}"
SSH_IDENTITY="${SSH_IDENTITY:-$HOME/.ssh/hetzner_scootercheck}"
REMOTE_APP="${REMOTE_APP:-/opt/scootercheck/firmware-analysis}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8088/health}"
CONFIRM_PROD_DEPLOY="${CONFIRM_PROD_DEPLOY:-NO}"
DRY_RUN=1
if [[ "$CONFIRM_PROD_DEPLOY" == "YES" ]]; then
  DRY_RUN=0
fi

PHASE1_FILES=(
  zip_safe.py
  app.py
  stock_diff.py
  test_zip_safe.py
  README.md
)

SSH=(ssh -i "$SSH_IDENTITY" -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)
RSYNC=(rsync -az --checksum)
if [[ -f "$SSH_IDENTITY" ]]; then
  RSYNC+=(-e "ssh -i $SSH_IDENTITY -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new")
fi

log() { printf '[phase1-rollout] %s\n' "$*" >&2; }
die() { printf '[phase1-rollout] ERROR: %s\n' "$*" >&2; exit 1; }

remote() {
  # shellcheck disable=SC2029
  "${SSH[@]}" "$REMOTE_HOST" "$@"
}

require_local_files() {
  local f
  for f in "${PHASE1_FILES[@]}"; do
    [[ -f "$APP_SRC/$f" ]] || die "missing local file: $APP_SRC/$f"
  done
  log "local Phase-1 files present under $APP_SRC"
}

preflight_ssh() {
  remote "test -d '$REMOTE_APP'" || die "remote app dir missing: $REMOTE_APP"
  remote "test -x '$REMOTE_APP/.venv/bin/python'" || die "remote venv python missing"
  remote "systemctl cat '$SERVICE_NAME' >/dev/null" || die "systemd unit missing: $SERVICE_NAME"
  log "SSH preflight OK ($REMOTE_HOST)"
}

run_local_tests() {
  log "local unit tests…"
  (
    cd "$APP_SRC"
    python3 -m unittest discover -p 'test_*.py' -q
  ) || die "local unit tests failed — aborting before any remote change"
  log "local unit tests OK"
}

backup_remote() {
  local stamp backup
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup="${REMOTE_APP}.bak-phase1-${stamp}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would create backup $backup"
    printf '%s\n' "$backup"
    return 0
  fi
  log "creating remote backup → $backup"
  # Copy tree only; do not touch /var/lib/scootercheck.
  if ! remote "cp -a -- '$REMOTE_APP' '$backup'"; then
    die "backup failed — deployment aborted (no files changed)"
  fi
  # Verify backup looks complete.
  if ! remote "test -f '$backup/app.py' && test -d '$backup'"; then
    die "backup verification failed — deployment aborted"
  fi
  # Refuse to continue if backup is empty-ish.
  local count
  count="$(remote "find '$backup' -maxdepth 1 -type f -name '*.py' | wc -l" | tr -d '[:space:]')"
  [[ "${count:-0}" -ge 5 ]] || die "backup too small ($count py files) — aborting"
  log "backup OK ($count top-level .py files)"
  printf '%s\n' "$backup"
}

sync_files() {
  local f
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would rsync into $REMOTE_APP:"
    for f in "${PHASE1_FILES[@]}"; do
      log "  - $f"
    done
    return 0
  fi
  for f in "${PHASE1_FILES[@]}"; do
    log "rsync $f → $REMOTE_APP/$f"
    # Explicit destination file path — avoids --relative path surprises.
    "${RSYNC[@]}" "$APP_SRC/$f" "$REMOTE_HOST:$REMOTE_APP/$f" \
      || die "rsync failed for $f — run rollback manually if partial"
  done
  remote "chown -R scootercheck:scootercheck -- '$REMOTE_APP'" \
    || die "chown failed after sync"
  # Ensure we never synced into /var/lib
  remote "test ! -e /var/lib/scootercheck/zip_safe.py" || die "unexpected file under /var/lib"
}

remote_import_and_tests() {
  local cmd
  cmd=$(cat <<EOF
set -euo pipefail
cd '$REMOTE_APP'
./.venv/bin/python -c 'import zip_safe, stock_diff, app; print("imports_ok")'
./.venv/bin/python -m unittest test_zip_safe test_stock_diff -q
EOF
)
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would run remote imports + unit tests"
    (
      cd "$APP_SRC"
      python3 -c 'import zip_safe, stock_diff; print("local_imports_ok")'
      python3 -m unittest test_zip_safe test_stock_diff -q
    ) || return 1
    return 0
  fi
  log "remote import check + unit tests…"
  if ! remote "$cmd"; then
    log "remote import/tests failed — refusing restart"
    return 1
  fi
  log "remote import/tests OK"
  return 0
}

restart_and_healthcheck() {
  local backup="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would restart $SERVICE_NAME and healthcheck $HEALTH_URL"
    return 0
  fi
  log "restarting $SERVICE_NAME…"
  remote "systemctl restart '$SERVICE_NAME'" || {
    log "restart failed — attempting rollback"
    rollback "$backup"
    die "restart failed; rolled back"
  }
  # Wait briefly for bind
  sleep 2
  local health
  if ! health="$(remote "curl -fsS --max-time 10 '$HEALTH_URL'")"; then
    log "healthcheck failed — rolling back"
    rollback "$backup"
    die "healthcheck failed; rolled back to $backup"
  fi
  printf '%s\n' "$health" | grep -q '"ok"[[:space:]]*:[[:space:]]*true' \
    || {
      log "health payload missing ok=true — rolling back"
      rollback "$backup"
      die "unhealthy response; rolled back"
    }
  log "healthcheck OK"
  printf '%s\n' "$health"
}

rollback() {
  local backup="$1"
  [[ -n "$backup" ]] || die "rollback requested but backup path empty"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would restore $backup → $REMOTE_APP"
    return 0
  fi
  log "ROLLBACK: restoring $backup → $REMOTE_APP"
  # Replace app tree only. Never touch /var/lib/scootercheck.
  remote "systemctl stop '$SERVICE_NAME' || true"
  remote "rm -rf -- '${REMOTE_APP}.failed-phase1' && mv -- '$REMOTE_APP' '${REMOTE_APP}.failed-phase1' && cp -a -- '$backup' '$REMOTE_APP'"
  remote "chown -R scootercheck:scootercheck -- '$REMOTE_APP'"
  remote "systemctl start '$SERVICE_NAME'"
  sleep 2
  remote "curl -fsS --max-time 10 '$HEALTH_URL' >/dev/null" \
    || die "rollback started service but healthcheck still failing"
  log "ROLLBACK complete; previous attempt kept at ${REMOTE_APP}.failed-phase1"
}

main() {
  log "repo=$REPO_ROOT"
  log "src=$APP_SRC"
  log "remote=$REMOTE_HOST:$REMOTE_APP"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "mode=DRY-RUN (set CONFIRM_PROD_DEPLOY=YES for real deploy)"
  else
    log "mode=LIVE DEPLOY — production will be modified"
  fi

  require_local_files
  run_local_tests
  preflight_ssh

  local backup
  backup="$(backup_remote)"
  [[ -n "$backup" ]] || die "empty backup path"

  # Sync before restart; on test failure after sync, rollback.
  sync_files
  if ! remote_import_and_tests; then
    if [[ "$DRY_RUN" -eq 0 ]]; then
      rollback "$backup"
    fi
    die "post-sync validation failed — restart not performed"
  fi
  restart_and_healthcheck "$backup"
  log "done. data under /var/lib/scootercheck was not modified."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN finished — no production changes."
  fi
}

main "$@"
