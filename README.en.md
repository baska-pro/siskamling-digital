## Screenshot

<p align="center">
  <img src="assets/screenshots/aktivasi.jpg" width="45%" alt="Aktivasi Siskamling Digital">
  <img src="assets/screenshots/masuk.jpg" width="45%" alt="Login Siskamling Digital">
</p>

# Siskamling Digital

Siskamling Digital v6.10.0 is an all-in-one Bash installer that generates and runs a FastAPI backend, responsive PWA frontend, SQLite database, Web Push configuration, migration utilities, backups and service files.

## Quick start

```bash
git clone https://github.com/baska-pro/siskamling-digital.git
cd siskamling-digital
chmod +x siskamling.sh
./siskamling.sh
```

For persistent systemd services after the first successful install:

```bash
./scripts/install-systemd.sh
```

Run `bash tests/smoke.sh` before contributing. Never commit `.env`, databases, VAPID private keys, uploads, logs or backups.

See [README.md](README.md) for the full Indonesian documentation.
