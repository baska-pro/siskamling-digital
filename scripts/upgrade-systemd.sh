#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ "$(id -u)" -eq 0 ]; then SUDO=(); elif command -v sudo >/dev/null 2>&1; then SUDO=(sudo); else
  echo "Butuh root/sudo untuk upgrade instalasi systemd."; exit 1
fi

managed=0
if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled siskamling.service >/dev/null 2>&1; then
  managed=1
  "${SUDO[@]}" systemctl stop siskamling.service siskamling-db.service 2>/dev/null || true
fi

[ -x ./backup.sh ] && ./backup.sh || true
git pull --ff-only
./siskamling.sh

if [ "$managed" -eq 1 ]; then
  # Hentikan instance background yang dibuat installer, lalu kembalikan ke systemd.
  for pf in .pid_app .pid_dbweb; do
    if [ -f "$pf" ]; then
      pid="$(cat "$pf" 2>/dev/null || true)"
      [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  "${SUDO[@]}" install -m 0644 siskamling.service /etc/systemd/system/siskamling.service
  "${SUDO[@]}" install -m 0644 siskamling-db.service /etc/systemd/system/siskamling-db.service
  "${SUDO[@]}" systemctl daemon-reload
  "${SUDO[@]}" systemctl restart siskamling.service siskamling-db.service
fi

echo "[OK] Upgrade selesai."
