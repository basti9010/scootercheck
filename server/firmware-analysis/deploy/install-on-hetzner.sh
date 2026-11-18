#!/usr/bin/env bash
# Run ON the Hetzner VPS as root (after code is copied to /opt/scootercheck/firmware-analysis).
# Does not install ninebottea from the internet — copies host install or uses NINEBOTTEA_SRC.
set -euo pipefail

APP_DIR=/opt/scootercheck/firmware-analysis
ENV_FILE=/etc/scootercheck/firmware-analysis.env
JOB_DIR=/var/lib/scootercheck/firmware-jobs
SERVICE_SRC="$APP_DIR/deploy/scootercheck-fw.service"
NGINX_SNIPPET_SRC="$APP_DIR/deploy/nginx-scootercheck-fw.conf"
AUTH_ENV=/opt/scootercheck/.env

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing $APP_DIR — copy server/firmware-analysis there first." >&2
  exit 1
fi

id scootercheck &>/dev/null || useradd --system --home /var/lib/scootercheck --shell /usr/sbin/nologin scootercheck
STOCK_DIR=/var/lib/scootercheck/stock-fw
mkdir -p /etc/scootercheck "$JOB_DIR" /var/lib/scootercheck/decrypted /var/lib/scootercheck/decompiled "$STOCK_DIR"
chown -R scootercheck:scootercheck /var/lib/scootercheck
touch "$STOCK_DIR/.gitkeep"

JWT_FROM_AUTH=""
if [[ -f "$AUTH_ENV" ]]; then
  JWT_FROM_AUTH=$(grep -E '^JWT_SECRET=' "$AUTH_ENV" | head -1 | cut -d= -f2- || true)
fi

if [[ ! -f "$ENV_FILE" ]]; then
  umask 077
  TOKEN=$(openssl rand -hex 24)
  cat >"$ENV_FILE" <<EOF
API_TOKEN=${TOKEN}
JWT_SECRET=${JWT_FROM_AUTH}
JWT_ALGORITHM=HS256
DECRYPT_CMD=/opt/scootercheck/decrypt-firm.sh
WORK_DIR=/var/lib/scootercheck/firmware-jobs
PLAINTEXT_STORE=/var/lib/scootercheck/decrypted
DECOMPILE_STORE=/var/lib/scootercheck/decompiled
ENABLE_GHIDRA=1
GHIDRA_HOME=/opt/ghidra
GHIDRA_PROCESSOR=ARM:LE:32:Cortex
GHIDRA_BASE_ADDR=0x08000000
HOST=127.0.0.1
PORT=8088
STOCK_FW_DIR=/var/lib/scootercheck/stock-fw
EOF
  chmod 600 "$ENV_FILE"
  echo "Created $ENV_FILE"
else
  # Keep JWT in sync with auth service when possible.
  if [[ -n "$JWT_FROM_AUTH" ]] && ! grep -q '^JWT_SECRET=.\+' "$ENV_FILE"; then
    echo "JWT_SECRET=${JWT_FROM_AUTH}" >>"$ENV_FILE"
  fi
fi

# Ensure LLM placeholders exist (do not overwrite an existing key).
if ! grep -q '^LLM_API_KEY=' "$ENV_FILE" 2>/dev/null; then
  {
    echo ""
    echo "# Optional schema-bound KI (OpenAI-compatible). Leave empty to skip."
    echo "LLM_API_KEY="
    echo "LLM_BASE_URL=https://api.openai.com/v1"
    echo "LLM_MODEL=gpt-4o-mini"
  } >>"$ENV_FILE"
  echo "Appended LLM_* placeholders to $ENV_FILE"
elif ! grep -q '^LLM_MODEL=' "$ENV_FILE" 2>/dev/null; then
  echo "LLM_MODEL=gpt-4o-mini" >>"$ENV_FILE"
fi

if ! grep -q '^STOCK_FW_DIR=' "$ENV_FILE" 2>/dev/null; then
  echo "STOCK_FW_DIR=/var/lib/scootercheck/stock-fw" >>"$ENV_FILE"
fi

# angr CFGFast guards (safe defaults for 4 GB VPS)
grep -q '^ENABLE_ANGR=' "$ENV_FILE" 2>/dev/null || echo "ENABLE_ANGR=1" >>"$ENV_FILE"
grep -q '^ANGR_MAX_BYTES=' "$ENV_FILE" 2>/dev/null || echo "ANGR_MAX_BYTES=262144" >>"$ENV_FILE"
grep -q '^ANGR_TIMEOUT_SEC=' "$ENV_FILE" 2>/dev/null || echo "ANGR_TIMEOUT_SEC=90" >>"$ENV_FILE"
grep -q '^ANGR_MEM_MB=' "$ENV_FILE" 2>/dev/null || echo "ANGR_MEM_MB=1800" >>"$ENV_FILE"

if [[ ! -f /opt/scootercheck/decrypt-firm.sh ]]; then
  install -m 755 "$APP_DIR/decrypt-firm.example.sh" /opt/scootercheck/decrypt-firm.sh
fi

if [[ ! -f /etc/scootercheck/decrypt.env ]]; then
  umask 077
  cat >/etc/scootercheck/decrypt.env <<'EOF'
# Path to ninebottea inside the firmware-analysis venv (preferred) or absolute binary.
NINEBOTTEA_BIN=/opt/scootercheck/firmware-analysis/.venv/bin/ninebottea
# Optional: KEY=fe80... only on the server — never commit.
EOF
  chmod 640 /etc/scootercheck/decrypt.env
  chown root:scootercheck /etc/scootercheck/decrypt.env
fi
# Wrapper runs as scootercheck — must be able to source decrypt.env
chown root:scootercheck /etc/scootercheck/decrypt.env 2>/dev/null || true
chmod 640 /etc/scootercheck/decrypt.env 2>/dev/null || true

apt-get update -y
apt-get install -y python3.12 python3.12-venv python3-pip radare2

cd "$APP_DIR"
# Python 3.14 lacks wheels for pinned pydantic-core — use 3.12 like the auth service.
rm -rf .venv
python3.12 -m venv .venv
.venv/bin/pip install -U pip
.venv/bin/pip install -r requirements.txt
# Capstone + YARA are in requirements.txt; ensure rules dir is readable
chmod -R a+rX "$APP_DIR/yara_rules" 2>/dev/null || true

# Install already-present ninebottea into the service venv (ProtectHome blocks /root).
NINEBOT_SRC="${NINEBOTTEA_SRC:-/root/ninebottea/.venv/lib/python3.14/site-packages/ninebottea}"
NINEBOT_META="${NINEBOTTEA_META:-/root/ninebottea/.venv/lib/python3.14/site-packages/ninebottea-0.2.0.dist-info}"
if [[ -d "$NINEBOT_SRC" ]]; then
  SITE=$(.venv/bin/python -c 'import site; print(site.getsitepackages()[0])')
  rm -rf "$SITE/ninebottea" "$SITE"/ninebottea-*.dist-info
  cp -a "$NINEBOT_SRC" "$SITE/ninebottea"
  if [[ -d "$NINEBOT_META" ]]; then
    cp -a "$NINEBOT_META" "$SITE/$(basename "$NINEBOT_META")"
  fi
  cat >"$SITE/ninebottea_cli.py" <<'PY'
from ninebottea.__main__ import main
if __name__ == "__main__":
    raise SystemExit(main())
PY
  # Prefer package console script if present; else wrapper.
  if [[ ! -x .venv/bin/ninebottea ]]; then
    cat >.venv/bin/ninebottea <<EOF
#!/usr/bin/env bash
exec "$(pwd)/.venv/bin/python" -m ninebottea "\$@"
EOF
    chmod 755 .venv/bin/ninebottea
  fi
  .venv/bin/ninebottea --help >/dev/null
  echo "ninebottea installed into firmware-analysis venv"
else
  echo "WARNING: ninebottea sources not found at $NINEBOT_SRC — set NINEBOTTEA_BIN in decrypt.env" >&2
fi

chown -R scootercheck:scootercheck "$APP_DIR" /var/lib/scootercheck

install -m 644 "$SERVICE_SRC" /etc/systemd/system/scootercheck-fw.service
if [[ -f "$NGINX_SNIPPET_SRC" ]]; then
  install -m 644 "$NGINX_SNIPPET_SRC" /etc/nginx/snippets/scootercheck-fw.conf
fi

systemctl daemon-reload
systemctl enable --now scootercheck-fw.service
systemctl --no-pager status scootercheck-fw.service || true

echo
echo "Next:"
echo "  1) Ensure /etc/nginx/... includes snippets/scootercheck-fw.conf and reload nginx"
echo "  2) App default URL: https://api.tuningscanner.de/scootercheck-fw"
echo "  3) Auth: Bearer JWT (active user) or X-ScooterCheck-Token from $ENV_FILE"
echo "  4) curl -sS https://api.tuningscanner.de/scootercheck-fw/health"
