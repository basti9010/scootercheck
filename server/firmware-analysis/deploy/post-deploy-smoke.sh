#!/usr/bin/env bash
# Post-deploy smoke on host. CONFIGURED health flags ≠ VERIFIED.
set -euo pipefail

HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8088/health}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
SMOKE_ADMIN_TOKEN="${SMOKE_ADMIN_TOKEN:-}"  # optional; never echo

log() { printf '[post-deploy-smoke] %s\n' "$*" >&2; }
die() { printf '[post-deploy-smoke] ERROR: %s\n' "$*" >&2; exit 1; }

# 1) systemd
if command -v systemctl >/dev/null; then
  systemctl is-active --quiet "$SERVICE_NAME" || die "systemd $SERVICE_NAME not active"
  log "systemd=$SERVICE_NAME ACTIVE"
else
  log "systemd unavailable — skip unit check"
fi

# 2–4) health
BODY=$(curl -fsS --max-time 15 "$HEALTH_URL") || die "health unreachable: $HEALTH_URL"
echo "$BODY" | grep -q '"ok"[[:space:]]*:[[:space:]]*true' || die "health ok!=true"
log "health HTTP OK (body redacted from secrets — keys not printed)"

# Auth mode signal (no tokens)
AUTH_MODE=$(echo "$BODY" | sed -n 's/.*"authMode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
log "authMode=${AUTH_MODE:-unknown}"
if [[ "${AUTH_MODE:-}" == "open" ]]; then
  die "authMode=open is unsafe for production smoke"
fi

# Worker / config flags — report as CONFIGURED only
for flag in decryptConfigured ghidraConfigured; do
  VAL=$(echo "$BODY" | sed -n "s/.*\"$flag\"[[:space:]]*:[[:space:]]*\\(true\\|false\\).*/\\1/p" | head -1)
  log "grade.$flag=${VAL:-missing} → at most CONFIGURED (not VERIFIED)"
done

# 5–8 optional diagnostics selftest (admin token required; never log token)
if [[ -n "$SMOKE_ADMIN_TOKEN" ]]; then
  BASE=$(echo "$HEALTH_URL" | sed 's#/health##')
  CODE=$(curl -sS -o /tmp/sc-diag.json -w '%{http_code}' --max-time 20 \
    -H "Authorization: Bearer ${SMOKE_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -X POST "${BASE}/v1/diagnostics/selftest" -d '{}' || true)
  log "diagnostics.selftest HTTP=$CODE (body not echoed)"
  rm -f /tmp/sc-diag.json
else
  log "diagnostics.selftest SKIPPED (no SMOKE_ADMIN_TOKEN) — not E2E"
fi

log "SMOKE_PASSED grades: DEPLOYED+AVAILABLE(health) — TEA/Ghidra still not END_TO_END_VERIFIED from flags alone"
echo "ok smoke"
