# Upgrade

Sebelum upgrade:

```bash
./backup.sh
cp .env .env.backup
```

Update source lalu jalankan installer lagi:

```bash
git pull --ff-only
./siskamling.sh
```

Script mendeteksi `app/ronda.db` dan masuk mode upgrade. Database existing, `.env`, upload, dan VAPID private key dipertahankan. Migrasi hanya menambah/melengkapi struktur yang diperlukan.

Jika aplikasi dijalankan oleh systemd/process supervisor, hentikan service lebih dulu agar port tidak langsung direbut kembali oleh proses lama, kemudian start kembali setelah upgrade.
