# Deployment

## Aplikasi

Aplikasi FastAPI default listen pada `0.0.0.0:8000`. Gunakan reverse proxy atau Cloudflare Tunnel untuk akses publik HTTPS.

## SQLite Web

SQLite Web default hanya listen pada `127.0.0.1`. Ini sengaja agar database tidak terbuka langsung ke LAN/internet.

Contoh Cloudflare Tunnel:

```yaml
ingress:
  - hostname: db.example.com
    service: http://127.0.0.1:8008
  - service: http_status:404
```

## systemd

Installer menghasilkan `siskamling.service` dan `siskamling-db.service`. Setelah instalasi pertama berhasil:

```bash
./scripts/install-systemd.sh
```

Helper menghentikan instance background installer, memasang kedua service, mengaktifkan autostart, dan menjalankannya melalui systemd.

Untuk upgrade setelah systemd aktif:

```bash
./scripts/upgrade-systemd.sh
```

## CORS

Untuk penggunaan web app same-origin, biarkan `CORS_ORIGINS=` kosong. Bila API harus dipanggil dari origin lain, isi daftar dipisahkan koma:

```env
CORS_ORIGINS=https://app.example.com,https://admin.example.com
```
