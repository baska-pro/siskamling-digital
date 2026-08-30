# Contributing

1. Buat branch dari `main`.
2. Jangan commit `.env`, database, upload, log, backup, atau private key.
3. Jalankan `bash tests/smoke.sh` sebelum push.
4. Buat Pull Request ke `main`.
5. CI harus hijau sebelum merge.

Perubahan pada `siskamling.sh` harus mempertahankan sifat upgrade-safe: database dan konfigurasi existing tidak boleh dihapus otomatis.
