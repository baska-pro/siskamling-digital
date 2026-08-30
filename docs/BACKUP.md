# Backup & Restore

Installer menghasilkan `backup.sh`. Secara default backup database dan uploads disimpan di `backups/` dan dipertahankan maksimal 30 versi terbaru per jenis.

Backup manual:

```bash
./backup.sh
```

Jika `crontab` tersedia, installer mendaftarkan backup setiap hari pukul 02:00.

## Restore database

1. Hentikan aplikasi.
2. Backup database aktif terlebih dahulu.
3. Salin file backup `.db` ke `app/ronda.db`.
4. Jalankan `PRAGMA integrity_check` bila diperlukan.
5. Jalankan kembali `./siskamling.sh` agar migrasi versi terbaru diterapkan.

Jangan commit file backup ke Git.
