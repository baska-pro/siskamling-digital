# Configuration

Configuration lives in `.env`, generated automatically on first install.

| Key | Default | Purpose |
| --- | --- | --- |
| `TOKEN_HOURS` | `10` | Login token lifetime |
| `APP_HOST` | `0.0.0.0` | FastAPI bind host |
| `PORT` | `8000` | Application port |
| `DB_WEB_HOST` | `127.0.0.1` | SQLite Web bind host |
| `DB_PORT` | `8008` | SQLite Web starting port |
| `DB_WEB_USERNAME` | `admin` | SQLite Web username metadata |
| `DB_WEB_PASSWORD` | random | SQLite Web password |
| `DEFAULT_ADMIN_ID` | `SA00001` | Bootstrap Super Admin ID |
| `DEFAULT_ADMIN_PASSWORD` | random | Bootstrap password |
| `DB_PUBLIC_HOST` | project value | Cloudflare hostname |
| `VAPID_SUBJECT` | mailto | Web Push VAPID subject |
| `APP_TIMEZONE` | `Asia/Jakarta` | Application timezone |
| `CORS_ORIGINS` | empty | Optional comma-separated API origins |

Do not commit `.env`.
