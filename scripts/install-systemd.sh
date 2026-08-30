#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v systemctl >/dev/null 2>&1 || { echo "systemd/systemctl tidak tersedia."; exit 1; }
[ -f "$ROOT/siskamling.service" ] || { echo "Jalankan ./siskamling.sh sekali agar service file dibuat."; exit 1; }
[ -f "$ROOT/siskamling-db.service" ] || { echo "Jalankan ./siskamling.sh sekali agar DB service file dibuat."; exit 1; }

if [ "$(id -u)" -eq 0 ]; then SUDO=(); elif command -v sudo >/dev/null 2>&1; then SUDO=(sudo); else
  echo "Butuh root/sudo untuk memasang system service."; exit 1
fi

for pf in .pid_app .pid_dbweb; do
  if [ -f "$ROOT/$pf" ]; then
    pid="$(cat "$ROOT/$pf" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
    fi
  fi
done

"${SUDO[@]}" install -m 0644 "$ROOT/siskamling.service" /etc/systemd/system/siskamling.service
"${SUDO[@]}" install -m 0644 "$ROOT/siskamling-db.service" /etc/systemd/system/siskamling-db.service
"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable --now siskamling.service siskamling-db.service
"${SUDO[@]}" systemctl --no-pager --full status siskamling.service siskamling-db.service || true

echo "[OK] systemd aktif. Service akan start otomatis setelah reboot."
