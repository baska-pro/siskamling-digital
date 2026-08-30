# Changelog

## Unreleased

Belum ada perubahan setelah release awal repository.

## 6.10.0 - 2026-08-30

### Added

- Repository-ready packaging untuk Siskamling Digital.
- `.env.example`, CI, smoke tests, dokumentasi deployment, backup, upgrade, konfigurasi, arsitektur, dan security.
- Helper systemd untuk autostart aplikasi + SQLite Web serta upgrade yang aman.
- Konfigurasi `APP_HOST`, `DB_WEB_HOST`, `CORS_ORIGINS`, dan bootstrap admin melalui `.env`.
- Password bootstrap Super Admin acak pada instalasi baru.

### Security

- Menghapus password Super Admin statis dari source publik.
- SQLite Web bind default menjadi `127.0.0.1` dan tetap dapat diubah melalui `.env`.
- CORS tidak lagi wildcard secara default.
- `.env` diberi permission `600` dan seluruh runtime secret/data dikecualikan dari Git.

### Preserved

- Seluruh fitur inti v6.10: backend FastAPI, frontend PWA, absensi, patroli, chat, SOS, iuran, kompensasi, Web Push, laporan, import/export, migrasi, backup, dan SQLite Web.
