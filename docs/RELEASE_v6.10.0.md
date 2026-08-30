# Siskamling Digital v6.10.0

First repository-ready release of Siskamling Digital v6.10.0.

## Highlights

- All-in-one Bash installer
- FastAPI backend + responsive PWA frontend
- Attendance and patrol management
- Ordered patrol checkpoints with GPS/radius and multiple photos
- Group chat, SOS, notifications, and Web Push
- Iuran and compensation management
- JSON/Excel import and export
- SQLite Web administration
- Safe database migration and automatic backups
- Random bootstrap credentials for new installations
- Safer localhost-only SQLite Web default

## Installation

```bash
git clone https://github.com/baska-pro/siskamling-digital.git
cd siskamling-digital
chmod +x siskamling.sh
./siskamling.sh
```

## Upgrade

```bash
git pull --ff-only
./backup.sh
./siskamling.sh
```

## License

MIT
