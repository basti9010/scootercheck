#!/usr/bin/env bash
# Sync chronological OEM stock archive onto the firmware-analysis host and register refs.
# Usage:
#   STOCK_HOST=root@vps ./deploy_stock_archive.sh
#   STOCK_HOST=root@vps STOCK_ARCHIVE_REMOTE=/var/lib/scootercheck/stock-archive ./deploy_stock_archive.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_LOCAL="${STOCK_ARCHIVE_LOCAL:-$ROOT/stock-archive}"
HOST="${STOCK_HOST:-}"
REMOTE_ARCHIVE="${STOCK_ARCHIVE_REMOTE:-/var/lib/scootercheck/stock-archive}"
REMOTE_STOCK="${STOCK_FW_REMOTE:-/var/lib/scootercheck/stock-fw}"
REMOTE_APP="${STOCK_APP_REMOTE:-/opt/scootercheck/firmware-analysis}"

if [[ ! -d "$ARCHIVE_LOCAL" ]]; then
  echo "Missing local archive: $ARCHIVE_LOCAL" >&2
  echo "Run: python3 sync_stock_firmwares.py" >&2
  exit 1
fi

if [[ -z "$HOST" ]]; then
  echo "Set STOCK_HOST (e.g. root@your-vps) to deploy." >&2
  echo "Local archive ready at $ARCHIVE_LOCAL ($(find "$ARCHIVE_LOCAL" -type f | wc -l) files)." >&2
  exit 2
fi

echo "→ rsync archive to $HOST:$REMOTE_ARCHIVE"
ssh "$HOST" "mkdir -p '$REMOTE_ARCHIVE' '$REMOTE_STOCK'"
rsync -avz --delete "$ARCHIVE_LOCAL"/ "$HOST:$REMOTE_ARCHIVE"/

echo "→ register OEM refs into $REMOTE_STOCK"
ssh "$HOST" "cd '$REMOTE_APP' && \
  STOCK_ARCHIVE_DIR='$REMOTE_ARCHIVE' STOCK_FW_DIR='$REMOTE_STOCK' \
  python3 - <<'PY'
from pathlib import Path
import json, os
from stock_diff import ensure_stock_dir, register_stock_file

root = Path(os.environ['STOCK_ARCHIVE_DIR'])
index = json.loads((root / 'index.json').read_text(encoding='utf-8'))
ensure_stock_dir()
n = 0
for items in index.get('chronological', {}).values():
    for e in items:
        path = root / e['archivePath']
        if not path.is_file():
            continue
        data = path.read_bytes()
        register_stock_file(
            data,
            label=f\"OEM {e['model'].upper()} {e['component']} {e['version']}\",
            model=e['model'],
            controller_type=e['component'],
            version=e['version'],
            source='oem',
            notes=f\"Synced from {e.get('source')} url={e.get('url')}\",
        )
        n += 1
print('registered', n)
PY"

echo "Done."
