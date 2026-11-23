#!/usr/bin/env bash
# Post-deploy smoke on host (and optional public URL).
#
# Checks:
#   1) systemctl is-active scootercheck-fw (sudo -n if needed)
#   2) curl health — ok=true; auth flags without dumping tokens
#   3) optional public HEALTH_PUBLIC_URL
#   4) optional diagnostics if SMOKE_ADMIN_TOKEN / ADMIN_API_TOKEN present
#
# Grades:
#   decryptConfigured / ghidraConfigured → at most CONFIGURED (≠ VERIFIED)
#   E2E = NO without Freigabe + real fixtures (this script never claims E2E)
set -euo pipefail

HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8088/health}"
HEALTH_PUBLIC_URL="${HEALTH_PUBLIC_URL:-https://api.tuningscanner.de/scootercheck-fw/health}"
PUBLIC_SMOKE="${PUBLIC_SMOKE:-1}"
SERVICE_NAME="${SERVICE_NAME:-scootercheck-fw}"
SMOKE_ADMIN_TOKEN="${SMOKE_ADMIN_TOKEN:-${ADMIN_API_TOKEN:-}}"
DIAGNOSTICS_PATH="${DIAGNOSTICS_PATH:-/v1/diagnostics/status}"

log() { printf '[post-deploy-smoke] %s\n' "$*" >&2; }
die() { printf '[post-deploy-smoke] ERROR: %s\n' "$*" >&2; exit 1; }
grade() { printf '[post-deploy-smoke] GRADE %s=%s\n' "$1" "$2" >&2; }

sysctl_cmd() {
  if systemctl "$@" 2>/dev/null; then
    return 0
  fi
  sudo -n systemctl "$@"
}

# Mask token for GitHub Actions if present
if [[ -n "${SMOKE_ADMIN_TOKEN:-}" && -n "${GITHUB_ACTIONS:-}" ]]; then
  printf '::add-mask::%s\n' "$SMOKE_ADMIN_TOKEN"
fi

# 1) systemd
if command -v systemctl >/dev/null; then
  sysctl_cmd is-active --quiet "$SERVICE_NAME" || die "systemd $SERVICE_NAME not active"
  log "systemd=$SERVICE_NAME ACTIVE"
  grade "systemd" "ACTIVE"
else
  log "systemd unavailable — skip unit check"
fi

parse_health() {
  local body="$1"
  local source="$2"
  printf '%s' "$body" | grep -q '"ok"[[:space:]]*:[[:space:]]*true' \
    || die "health ok!=true ($source)"

  local auth_mode grants jwt_cfg admin_cfg decrypt ghidra
  auth_mode=$(printf '%s' "$body" | sed -n 's/.*"authMode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  grants=$(printf '%s' "$body" | sed -n 's/.*"apiTokenGrantsAdmin"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -1)
  jwt_cfg=$(printf '%s' "$body" | sed -n 's/.*"jwtConfigured"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -1)
  admin_cfg=$(printf '%s' "$body" | sed -n 's/.*"adminApiTokenConfigured"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -1)
  decrypt=$(printf '%s' "$body" | sed -n 's/.*"decryptConfigured"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -1)
  ghidra=$(printf '%s' "$body" | sed -n 's/.*"ghidraConfigured"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -1)

  log "auth_probe($source): authMode=${auth_mode:-?} jwtConfigured=${jwt_cfg:-?} adminApiTokenConfigured=${admin_cfg:-?} apiTokenGrantsAdmin=${grants:-?}"
  if [[ "${auth_mode:-}" == "open" ]]; then
    die "authMode=open is unsafe for production smoke"
  fi
  if [[ "$grants" == "true" ]]; then
    log "WARN: apiTokenGrantsAdmin=true (shared-token-admin) — security follow-up, not smoke failure"
  fi

  if [[ "$decrypt" == "true" ]]; then
    grade "TEA_${source}" "CONFIGURED (≠ VERIFIED — no decrypt job executed)"
  else
    grade "TEA_${source}" "NOT_CONFIGURED"
  fi
  if [[ "$ghidra" == "true" ]]; then
    grade "Ghidra_${source}" "CONFIGURED (≠ VERIFIED — no headless job executed)"
  else
    grade "Ghidra_${source}" "NOT_CONFIGURED"
  fi
}

# 2) loopback / configured health
BODY=$(curl -fsS --max-time 15 "$HEALTH_URL") || die "health unreachable: $HEALTH_URL"
log "health HTTP OK bytes=$(printf '%s' "$BODY" | wc -c | tr -d ' ') (body not dumped)"
parse_health "$BODY" "primary"
grade "health_primary" "PASS"

# 3) optional public URL (when primary is loopback)
if [[ "$PUBLIC_SMOKE" == "1" && "$HEALTH_URL" != "$HEALTH_PUBLIC_URL" ]]; then
  if PUB=$(curl -fsS --max-time 20 "$HEALTH_PUBLIC_URL" 2>/dev/null); then
    parse_health "$PUB" "public"
    grade "health_public" "PASS"
  else
    log "WARN: public health unreachable ($HEALTH_PUBLIC_URL) — non-fatal when primary passed"
    grade "health_public" "UNREACHABLE"
  fi
fi

# 4) optional diagnostics (admin token; never echo token or full body)
if [[ -n "$SMOKE_ADMIN_TOKEN" ]]; then
  BASE=$(printf '%s' "$HEALTH_URL" | sed 's#/health##')
  CODE=$(curl -sS -o /tmp/sc-diag.json -w '%{http_code}' --max-time 20 \
    -H "Authorization: Bearer ${SMOKE_ADMIN_TOKEN}" \
    "${BASE}${DIAGNOSTICS_PATH}" || true)
  log "diagnostics.status HTTP=$CODE (body not echoed)"
  if [[ "$CODE" == "200" ]]; then
    grade "diagnostics" "HTTP_200 (status only — not E2E job proof)"
  elif [[ "$CODE" == "401" || "$CODE" == "403" ]]; then
    grade "diagnostics" "AUTH_REJECTED HTTP_$CODE"
  elif [[ "$CODE" == "404" ]]; then
    grade "diagnostics" "NOT_WIRED HTTP_404"
  else
    grade "diagnostics" "UNEXPECTED_HTTP_$CODE"
  fi
  rm -f /tmp/sc-diag.json
else
  log "diagnostics SKIPPED (no SMOKE_ADMIN_TOKEN) — not E2E"
  grade "diagnostics" "SKIPPED"
fi

grade "END_TO_END_VERIFIED" "NO (no Freigabe / no real tuning fixtures in smoke)"
grade "E2E" "NO"
log "SMOKE_PASSED — DEPLOYED+AVAILABLE(health); TEA/Ghidra at most CONFIGURED"
echo "ok smoke"
