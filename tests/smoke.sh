#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash -n siskamling.sh
bash -n scripts/install-systemd.sh
bash -n scripts/upgrade-systemd.sh
grep -q 'Siskamling Digital v6.10.0' <<< "$(bash ./siskamling.sh --version)"
grep -q 'Usage:' <<< "$(bash ./siskamling.sh --help)"
test "$(tr -d '\r\n' < VERSION)" = "6.10.0"
grep -q 'VERSION = "6.10.0"' siskamling.sh
grep -q 'DEFAULT_ADMIN_PASSWORD = os.environ.get' siskamling.sh
! grep -q 'Password Ronda123' siskamling.sh
! grep -q 'DEFAULT_ADMIN_PASSWORD = "Ronda123"' siskamling.sh
grep -q 'DB_WEB_HOST=127.0.0.1' siskamling.sh
grep -q 'CORS_ORIGINS=' siskamling.sh
grep -q '^\.env$' .gitignore
grep -q 'app/ronda.db' .gitignore
grep -q 'siskamling-db.service' .gitignore

python3 - <<'PY'
from pathlib import Path
import json
s=Path('siskamling.sh').read_text()

def block(start,end):
    a=s.index(start)+len(start)
    b=s.index(end,a)
    return s[a:b].lstrip('\n')

compile(block("cat > \"$APP_DIR/main.py\" << 'SKPYEOF'", "\nSKPYEOF"), 'main.py', 'exec')
compile(block("python3 - \"$APP_DIR\" << 'MIGEOF'", "\nMIGEOF"), 'migration.py', 'exec')
json.loads(block("cat > \"$APP_DIR/static/manifest.json\" << 'MFEOF'", "\nMFEOF"))
print('[OK] embedded Python + manifest valid')
PY

echo "[OK] smoke tests passed"
