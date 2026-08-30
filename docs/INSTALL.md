# Instalasi

## Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip cron tar git
git clone https://github.com/baska-pro/siskamling-digital.git
cd siskamling-digital
chmod +x siskamling.sh
./siskamling.sh
```

Installer akan membuat `app/`, `venv/`, `.env`, `uploads/`, `logs/`, `backups/`, file backup, service example, database/migrasi, VAPID key, lalu menjalankan aplikasi dan SQLite Web.

## Port default

- Aplikasi: `8000`, bind `0.0.0.0`.
- SQLite Web: mulai `8008`, bind `127.0.0.1`.

Keduanya dapat diubah di `.env`.

## Verifikasi

```bash
curl -fsS http://127.0.0.1:8000/health
cat .pid_app
cat .pid_dbweb
```

Password bootstrap dan password SQLite Web ditampilkan pada akhir instalasi. Simpan dengan aman.
