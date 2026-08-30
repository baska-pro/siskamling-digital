## Screenshot

<p align="center">
  <img src="assets/screenshots/aktivasi.jpg" width="45%" alt="Aktivasi Siskamling Digital">
  <img src="assets/screenshots/masuk.jpg" width="45%" alt="Login Siskamling Digital">
</p>

# Siskamling Digital

[![CI](https://github.com/baska-pro/siskamling-digital/actions/workflows/ci.yml/badge.svg)](https://github.com/baska-pro/siskamling-digital/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/baska-pro/siskamling-digital?style=flat-square)](https://github.com/baska-pro/siskamling-digital/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

**Siskamling Digital v6.10.0** adalah aplikasi PWA + API untuk pengelolaan ronda/siskamling. Project tetap memakai konsep **single all-in-one Bash installer**: `siskamling.sh` menghasilkan backend FastAPI, frontend PWA, konfigurasi, migrasi database, backup, Web Push, dan file service yang diperlukan.

## Fitur utama

- login ID/No. HP + password dan aktivasi perangkat;
- role Super Admin, Admin, Koordinator, dan Warga;
- absensi check-in/check-out dengan jadwal;
- rute patroli berurutan, GPS, radius checkpoint, dan multi-foto;
- ruang chat, reply, media, notifikasi, SOS;
- Web Push untuk chat/SOS/kompensasi;
- iuran dan tagihan kompensasi;
- pengganti ronda dan jadwal grup;
- export/import data JSON dan Excel;
- audit log, SQLite Web, backup otomatis, dan migrasi aman;
- PWA responsif untuk ponsel dan desktop.

## Instalasi cepat

```bash
git clone https://github.com/baska-pro/siskamling-digital.git
cd siskamling-digital
chmod +x siskamling.sh
./siskamling.sh
```

Installer mempertahankan database dan `.env` pada upgrade. Secret baru dibuat otomatis pada instalasi pertama.

## Prasyarat

Linux dengan Python 3 + `venv`, `tar`, dan koneksi internet untuk instalasi dependency Python. `crontab` bersifat opsional tetapi diperlukan untuk backup otomatis pukul 02:00.

Debian/Ubuntu:

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip cron tar git
```

## Setelah instalasi

```bash
curl -fsS http://127.0.0.1:8000/health
tail -f logs/server.log
```

Simpan password bootstrap yang ditampilkan installer, login sebagai `SA00001`, lalu ganti password. Untuk start otomatis setelah reboot, jalankan `./scripts/install-systemd.sh` setelah instalasi pertama berhasil. Jangan commit `.env`, database, private key VAPID, upload, log, atau backup.

## Dokumentasi

- [Instalasi](docs/INSTALL.md)
- [Konfigurasi](docs/CONFIGURATION.md)
- [Arsitektur](docs/ARCHITECTURE.md)
- [Deployment](docs/DEPLOYMENT.md)
- [Upgrade](docs/UPGRADE.md)
- [Backup & Restore](docs/BACKUP.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Lisensi

MIT.
