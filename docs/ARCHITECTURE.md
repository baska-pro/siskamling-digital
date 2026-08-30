# Architecture

`Siskamling Digital` intentionally keeps the application source in one repository entry point: `siskamling.sh`.

On install/upgrade it generates:

```text
app/
├── main.py
├── index.html
├── requirements.txt
└── static/
    ├── sw.js
    ├── manifest.json
    └── icon.svg

uploads/
logs/
backups/
venv/
.env
backup.sh
siskamling.service
siskamling-db.service
cloudflare-db-route.yml.example
```

`main.py` provides FastAPI + SQLAlchemy + SQLite, authentication, attendance, patrol, chat, notifications, Web Push, reports and administration. `index.html` contains the responsive PWA UI. Runtime/generated files are intentionally ignored by Git so production data cannot be committed accidentally.
