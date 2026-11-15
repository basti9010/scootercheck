#!/usr/bin/env bash
# Run ON the Hetzner VPS as root (after code is copied to /opt/scootercheck).
# Does not install ninebottea — only the worker + systemd. Wire DECRYPT_CMD yourself.
set -euo pipefail

APP_DIR=/opt/scootercheck/firmware-analysis
ENV_FILE=/etc/scootercheck/firmware-analysis.env
JOB_DIR=/var/lib/scootercheck/firmware-jobs
SERVICE_SRC="$APP_DIR/deploy/scootercheck-fw.service"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing $APP_DIR — copy server/firmware-analysis there first." >&2
  exit 1
fi

id scootercheck &>/dev/null || useradd --system --home /var/lib/scootercheck --shell /usr/sbin/nologin scootercheck
mkdir -p /etc/scootercheck "$JOB_DIR"
chown -R scootercheck:scootercheck /var/lib/scootercheck

if [[ ! -f "$ENV_FILE" ]]; then
  umask 077
  cat >"$ENV_FILE" <<'EOF'
API_TOKEN=change-me-long-random
DECRYPT_CMD=/opt/scootercheck/decrypt-firm.sh
WORK_DIR=/var/lib/scootercheck/firmware-jobs
HOST=127.0.0.1
PORT=8088
EOF
  chmod 600 "$ENV_FILE"
  echo "Created $ENV_FILE — set API_TOKEN and DECRYPT_CMD."
fi

apt-get update -y
apt-get install -y python3 python3-venv python3-pip

cd "$APP_DIR"
python3 -m venv .venv
.venv/bin/pip install -U pip
.venv/bin/pip install -r requirements.txt
chown -R scootercheck:scootercheck "$APP_DIR"

install -m 644 "$SERVICE_SRC" /etc/systemd/system/scootercheck-fw.service
systemctl daemon-reload
systemctl enable --now scootercheck-fw.service
systemctl --no-pager status scootercheck-fw.service || true

echo
echo "Next:"
echo "  1) Edit $ENV_FILE (API_TOKEN, DECRYPT_CMD → your installed decrypt wrapper)"
echo "  2) Put decrypt wrapper at /opt/scootercheck/decrypt-firm.sh (input.enc output.bin)"
echo "  3) Optional: nginx + TLS (deploy/nginx-fw.conf.example)"
echo "  4) App Settings → https://YOUR-HETZNER-HOST + same API_TOKEN"
echo "  5) curl -H \"X-ScooterCheck-Token: …\" https://YOUR-HETZNER-HOST/health"
