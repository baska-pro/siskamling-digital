# Security Policy

## Supported version

Versi yang didukung saat ini: `6.10.x`.

## Data sensitif

Jangan pernah commit atau mengirim melalui issue publik:

- `.env`;
- `app/ronda.db` dan file WAL/SHM;
- `app/vapid_private.pem`;
- folder `uploads/`, `logs/`, `backups/`;
- password, token, private key, atau hasil export database.

Installer v6.10.0 membuat password bootstrap Super Admin dan SQLite Web secara acak pada instalasi baru. Ganti password Super Admin setelah login pertama.

SQLite Web default bind ke `127.0.0.1`. Jika dipublikasikan melalui Cloudflare Tunnel, arahkan tunnel ke localhost dan jangan membuka port database langsung ke internet.

## Melaporkan kerentanan

Jangan membuat public issue berisi exploit aktif, credential, atau data warga. Laporkan secara privat kepada maintainer repository.
