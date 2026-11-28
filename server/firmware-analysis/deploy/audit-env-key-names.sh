#!/usr/bin/env bash
# Ops helper (run ON the VPS as root). Prints KEY NAMES only — never values.
# Cycle 13: catch hyphenated systemd EnvironmentFile dead-keys.
set -euo pipefail

ENV_FILE="${1:-/etc/scootercheck/firmware-analysis.env}"
[[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || echo "WARN: prefer root so the file is readable" >&2

echo "=== key names in $ENV_FILE ==="
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | cut -d= -f1 | sort -u || true

echo
echo "=== suspicious hyphenated assignments (systemd ignores these) ==="
if grep -E '^[A-Za-z0-9_-]*-[A-Za-z0-9_-]*=' "$ENV_FILE" >/dev/null 2>&1; then
  grep -E '^[A-Za-z0-9_-]*-[A-Za-z0-9_-]*=' "$ENV_FILE" | cut -d= -f1
else
  echo "(none)"
fi

echo
echo "=== expected underscore keys (presence only) ==="
for k in API_TOKEN ADMIN_API_TOKEN API_TOKEN_GRANTS_ADMIN JWT_SECRET DECRYPT_CMD TRUST_API_TOKEN_CLIENT_ID; do
  if grep -qE "^${k}=" "$ENV_FILE"; then
    echo "PRESENT $k"
  else
    echo "MISSING $k"
  fi
done

echo
echo "Next (manual, values never in chat): fix hyphens → underscores,"
echo "set API_TOKEN_GRANTS_ADMIN=0, set ADMIN_API_TOKEN if approved,"
echo "chmod 600 $ENV_FILE, systemctl restart scootercheck-fw,"
echo "curl health | jq '{authMode,adminApiTokenConfigured,apiTokenGrantsAdmin,authSecurityOk}'"
