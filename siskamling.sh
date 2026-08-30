#!/bin/bash
# ==============================================================================
# SISKAMLING DIGITAL v6.10.0 — ALL-IN-ONE INSTALLER
# Aman dijalankan berkali-kali. Data tidak pernah dihapus.
# Cara pakai: chmod +x siskamling.sh && bash siskamling.sh
# ==============================================================================
set -euo pipefail
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info(){ echo -e "${GRN}[✔]${NC} $1"; }; warn(){ echo -e "${YLW}[!]${NC} $1"; }
section(){ echo -e "\n${CYN}${BOLD}━━ $1 ━━${NC}"; }

APP_VERSION="6.10.0"
show_help(){
  cat <<'EOF'
Siskamling Digital v6.10.0

Usage:
  ./siskamling.sh            Install / upgrade and start the application
  ./siskamling.sh --version  Show version
  ./siskamling.sh --help     Show this help

Runtime data, .env, uploads, backups and database are preserved on upgrade.
EOF
}
case "${1:-}" in
  --version|-V) echo "Siskamling Digital v$APP_VERSION"; exit 0 ;;
  --help|-h) show_help; exit 0 ;;
  "") ;;
  *) echo "Opsi tidak dikenal: $1" >&2; show_help >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/app"
IS_UP=false; [ -f "$APP_DIR/ronda.db" ] && IS_UP=true

clear
echo -e "${CYN}${BOLD}"
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │  🛡️   SISKAMLING DIGITAL v6.10.0 — ALL-IN-ONE          │"
echo "  └─────────────────────────────────────────────────────────┘${NC}"
$IS_UP && echo -e "  ${YLW}${BOLD}Mode: UPGRADE${NC} — data existing dipertahankan" \
       || echo -e "  ${GRN}${BOLD}Mode: INSTALASI BARU${NC}"
echo; sleep 1

section "CEK PRASYARAT"
command -v python3 >/dev/null 2>&1 || { echo -e "${RED}Python3 tidak ada. Install Python 3 terlebih dahulu.${NC}"; exit 1; }
python3 -c 'import venv' >/dev/null 2>&1 || { echo -e "${RED}Modul venv tidak tersedia. Debian/Ubuntu: sudo apt install python3-venv${NC}"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo -e "${RED}tar tidak tersedia. Install paket tar terlebih dahulu.${NC}"; exit 1; }
info "Python $(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")') terdeteksi"
command -v crontab >/dev/null 2>&1 || warn "crontab tidak tersedia — backup otomatis akan dilewati, backup.sh tetap dibuat"

section "PERSIAPAN"
if [ -f "$SCRIPT_DIR/.pid_app" ]; then
  PID=$(cat "$SCRIPT_DIR/.pid_app" 2>/dev/null||echo "")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill -TERM "$PID" 2>/dev/null; sleep 2; kill -9 "$PID" 2>/dev/null||true; warn "Server lama (PID $PID) dihentikan"
  fi
fi
if [ -f "$SCRIPT_DIR/.pid_dbweb" ]; then
  DBPID=$(cat "$SCRIPT_DIR/.pid_dbweb" 2>/dev/null||echo "")
  if [ -n "$DBPID" ] && kill -0 "$DBPID" 2>/dev/null; then
    kill -TERM "$DBPID" 2>/dev/null||true; sleep 1; kill -9 "$DBPID" 2>/dev/null||true; warn "SQLite Web lama (PID $DBPID) dihentikan"
  fi
fi
sleep 1; info "Proses lama bersih"

section "STRUKTUR FOLDER"
mkdir -p "$APP_DIR/static"
mkdir -p "$SCRIPT_DIR"/{uploads/{profile,ronda,laporan,qr},logs,backups}
chmod -R 755 "$SCRIPT_DIR/uploads" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/backups"
info "Folder siap"

section "KONFIGURASI (.env)"
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  SK=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
  ADMIN_PW=$(python3 -c "import secrets; print('A1-'+secrets.token_urlsafe(14))")
  cat > "$SCRIPT_DIR/.env" << ENVEOF
# SISKAMLING DIGITAL v6.10.0
SK=$SK
TOKEN_HOURS=10
APP_HOST=0.0.0.0
PORT=8000
DB_WEB_HOST=127.0.0.1
DB_PORT=8008
DB_WEB_USERNAME=admin
DB_WEB_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")
DEFAULT_ADMIN_ID=SA00001
DEFAULT_ADMIN_PASSWORD=$ADMIN_PW
DB_PUBLIC_HOST=db-ronda.lavi.web.id
VAPID_SUBJECT=mailto:admin@ronda.lavi.web.id
APP_TIMEZONE=Asia/Jakarta
CORS_ORIGINS=
ENVEOF
  chmod 600 "$SCRIPT_DIR/.env"
  info ".env baru dibuat dengan secret acak"
else
  info ".env sudah ada — dipertahankan"
fi

# Tambahkan key baru yang belum ada tanpa menimpa konfigurasi existing.
python3 - "$SCRIPT_DIR/.env" <<'PYENV'
import secrets,sys
from pathlib import Path
p=Path(sys.argv[1]); lines=p.read_text().splitlines() if p.exists() else []
existing={line.split("=",1)[0].strip() for line in lines if "=" in line and not line.lstrip().startswith("#")}
def admin_password(): return "A1-"+secrets.token_urlsafe(14)
defs={
    "SK":secrets.token_urlsafe(32),"TOKEN_HOURS":"10","APP_HOST":"0.0.0.0","PORT":"8000",
    "DB_WEB_HOST":"127.0.0.1","DB_PORT":"8008","DB_WEB_USERNAME":"admin",
    "DB_WEB_PASSWORD":secrets.token_urlsafe(16),"DEFAULT_ADMIN_ID":"SA00001",
    "DEFAULT_ADMIN_PASSWORD":admin_password(),"DB_PUBLIC_HOST":"db-ronda.lavi.web.id",
    "VAPID_SUBJECT":"mailto:admin@ronda.lavi.web.id","APP_TIMEZONE":"Asia/Jakarta","CORS_ORIGINS":""
}
for k,v in defs.items():
    if k not in existing: lines.append(f"{k}={v}")
p.write_text("\n".join(lines)+"\n")
PYENV
chmod 600 "$SCRIPT_DIR/.env"
set -a
source "$SCRIPT_DIR/.env" 2>/dev/null || true
set +a
SK=${SK:-$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")}
APP_HOST=${APP_HOST:-0.0.0.0}; PORT=${PORT:-8000}
DB_WEB_HOST=${DB_WEB_HOST:-127.0.0.1}; DB_PORT=${DB_PORT:-8008}
DB_WEB_USERNAME=${DB_WEB_USERNAME:-admin}
DB_WEB_PASSWORD=${DB_WEB_PASSWORD:-$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")}
DEFAULT_ADMIN_ID=${DEFAULT_ADMIN_ID:-SA00001}
DEFAULT_ADMIN_PASSWORD=${DEFAULT_ADMIN_PASSWORD:-$(python3 -c "import secrets; print('A1-'+secrets.token_urlsafe(14))")}
DB_PUBLIC_HOST=${DB_PUBLIC_HOST:-db-ronda.lavi.web.id}
CORS_ORIGINS=${CORS_ORIGINS:-}

# SQLite Web memakai port kosong mulai DB_PORT dan bind host yang dapat dikonfigurasi.
DB_PORT=$(python3 - "$DB_PORT" <<'PY'
import socket,sys
p=max(1,min(65534,int(sys.argv[1])))
while p<65535:
    with socket.socket() as s:
        try: s.bind(("127.0.0.1",p)); print(p); break
        except OSError: p+=1
else: raise SystemExit("Tidak menemukan port kosong untuk SQLite Web")
PY
)
python3 - "$SCRIPT_DIR/.env" "$DB_PORT" "$DB_WEB_USERNAME" "$DB_WEB_PASSWORD" "$DB_PUBLIC_HOST" "$APP_HOST" "$DB_WEB_HOST" "$DEFAULT_ADMIN_ID" "$DEFAULT_ADMIN_PASSWORD" "$CORS_ORIGINS" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); keys=["DB_PORT","DB_WEB_USERNAME","DB_WEB_PASSWORD","DB_PUBLIC_HOST","APP_HOST","DB_WEB_HOST","DEFAULT_ADMIN_ID","DEFAULT_ADMIN_PASSWORD","CORS_ORIGINS"]
values=dict(zip(keys,sys.argv[2:]))
lines=p.read_text().splitlines() if p.exists() else []
seen=set(); out=[]
for line in lines:
    key=line.split("=",1)[0].strip() if "=" in line and not line.lstrip().startswith("#") else ""
    if key in values: out.append(f"{key}={values[key]}"); seen.add(key)
    else: out.append(line)
for key,val in values.items():
    if key not in seen: out.append(f"{key}={val}")
p.write_text("\n".join(out)+"\n")
PY
chmod 600 "$SCRIPT_DIR/.env"
info "SQLite Web akan memakai $DB_WEB_HOST:$DB_PORT"

section "GENERATE: requirements.txt"
cat > "$APP_DIR/requirements.txt" << 'REQEOF'
fastapi>=0.115.0
uvicorn[standard]>=0.30.0
sqlalchemy>=2.0.36
python-multipart>=0.0.9
pydantic>=2.9.0
python-jose[cryptography]>=3.3.0
bcrypt>=4.0.1
sqlite-web>=0.6.0
openpyxl>=3.1.5
Pillow>=10.4.0
pywebpush>=2.0.0
REQEOF
info "requirements.txt siap"

section "GENERATE: Static PWA Files"
cat > "$APP_DIR/static/sw.js" << 'SWEOF'
const CACHE="sk-v6100";const ASSETS=["/","/static/manifest.json"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).catch(()=>{}));self.skipWaiting();});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))));self.clients.claim();});
self.addEventListener("fetch",e=>{if(e.request.method!=="GET"||e.request.url.includes("/api/"))return;e.respondWith(fetch(e.request).catch(()=>caches.match(e.request)));});
self.addEventListener("push",e=>{let d={};try{d=e.data?e.data.json():{};}catch(_){d={title:"Siskamling",body:e.data?.text()||"Notifikasi baru"};}
  if(d.action==="close"){e.waitUntil(self.registration.getNotifications({tag:d.tag}).then(ns=>ns.forEach(n=>n.close())));return;}
  const o={body:d.body||"",icon:d.icon||"/static/icon.svg",badge:"/static/icon.svg",tag:d.tag||"siskamling",
    renotify:true,requireInteraction:d.type==="sos",vibrate:d.type==="sos"?[300,120,300,120,500]:[120,70,180],data:d.data||{url:"/"}};
  e.waitUntil(self.registration.showNotification(d.title||"Siskamling",o));});
self.addEventListener("notificationclick",e=>{e.notification.close();const target=e.notification.data?.url||"/";
  e.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{for(const c of list){if(new URL(c.url).origin===self.location.origin){c.postMessage({type:"PUSH_OPEN",target});return c.focus();}}return clients.openWindow(target);}));});
SWEOF
cat > "$APP_DIR/static/manifest.json" << 'MFEOF'
{"name":"Siskamling Digital","short_name":"Siskamling","description":"Sistem Keamanan Lingkungan Digital v6.10.0","start_url":"/","display":"standalone","orientation":"portrait","background_color":"#6366f1","theme_color":"#6366f1","icons":[{"src":"/static/icon.svg","sizes":"any","type":"image/svg+xml","purpose":"any maskable"}]}
MFEOF
python3 -c "
svg=b'<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 192 192\"><rect width=\"192\" height=\"192\" rx=\"36\" fill=\"#6366f1\"/><text y=\"135\" x=\"96\" text-anchor=\"middle\" font-size=\"108\" fill=\"white\">S</text></svg>'
open('$APP_DIR/static/icon.svg','wb').write(svg)
" && info "Icon SVG dibuat" || true
info "Static files siap"

section "GENERATE: backup.sh"
cat > "$SCRIPT_DIR/backup.sh" << 'BKEOF'
#!/bin/bash
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; TS=$(date +%Y%m%d_%H%M%S); MAX=30
mkdir -p "$D/backups"
[ -f "$D/app/ronda.db" ] && cp "$D/app/ronda.db" "$D/backups/ronda_$TS.db" && echo "[$(date)] DB OK"
tar -czf "$D/backups/uploads_$TS.tar.gz" -C "$D" uploads/ 2>/dev/null && echo "[$(date)] Upload OK" || true
ls -t "$D/backups/ronda_"*.db 2>/dev/null|tail -n +$((MAX+1))|xargs -r rm -f
ls -t "$D/backups/uploads_"*.tar.gz 2>/dev/null|tail -n +$((MAX+1))|xargs -r rm -f
BKEOF
chmod +x "$SCRIPT_DIR/backup.sh"; info "backup.sh siap"

section "GENERATE: systemd service"
cat > "$SCRIPT_DIR/siskamling.service" << SVCEOF
[Unit]
Description=Siskamling Digital v6.10.0
After=network.target
[Service]
Type=exec
User=$USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$SCRIPT_DIR/.env
Environment="VAPID_PRIVATE_KEY_PATH=$APP_DIR/vapid_private.pem"
ExecStart=$SCRIPT_DIR/venv/bin/uvicorn main:app --host $APP_HOST --port $PORT --workers 1 --access-log
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
SVCEOF
info "siskamling.service siap"

cat > "$SCRIPT_DIR/siskamling-db.service" << SVCEOF
[Unit]
Description=Siskamling Digital SQLite Web v6.10.0
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
EnvironmentFile=$SCRIPT_DIR/.env
ExecStart=/bin/bash -lc 'export SQLITE_WEB_PASSWORD="\$DB_WEB_PASSWORD"; exec "$SCRIPT_DIR/venv/bin/sqlite_web" --port "\$DB_PORT" --host "\$DB_WEB_HOST" --no-browser --password "$APP_DIR/ronda.db"'
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
SVCEOF
info "siskamling-db.service siap"

section "GENERATE: Cloudflare Tunnel Route Example"
cat > "$SCRIPT_DIR/cloudflare-db-route.yml.example" << CFEOF
# Gunakan hostname satu tingkat agar tercakup Universal SSL Cloudflare.
# Dashboard: Networking > Tunnels > pilih tunnel > Routes > Add route > Published application
# Public hostname: $DB_PUBLIC_HOST
# Service URL: http://127.0.0.1:$DB_PORT
ingress:
  - hostname: $DB_PUBLIC_HOST
    service: http://127.0.0.1:$DB_PORT
  - service: http_status:404
CFEOF
info "Contoh route Cloudflare dibuat: cloudflare-db-route.yml.example"


section "GENERATE: Backend API (main.py)"
cat > "$APP_DIR/main.py" << 'SKPYEOF'
import os, uuid, csv, io, json, secrets, logging, re, hashlib, hmac, base64, threading, time as time_module
from datetime import datetime, time, timedelta, date, timezone
from pathlib import Path
from typing import Optional, List
from zoneinfo import ZoneInfo
from math import radians, sin, cos, sqrt, atan2
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Request, Header
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Boolean, Text, func, or_, and_, UniqueConstraint
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from sqlalchemy import event as sa_event
from jose import JWTError, jwt
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill, Alignment
from PIL import Image, ImageOps
from pywebpush import webpush, WebPushException

BASE_DIR   = Path(__file__).parent.resolve()
UPLOAD_DIR = BASE_DIR.parent / "uploads"
LOG_DIR    = BASE_DIR.parent / "logs"
SECRET_KEY = os.environ.get("SK", secrets.token_urlsafe(32))
ALGORITHM  = "HS256"
TOKEN_HOURS= int(os.environ.get("TOKEN_HOURS", "10"))
APP_PORT   = int(os.environ.get("PORT", "8000"))
DB_PORT    = int(os.environ.get("DB_PORT", "8008"))
MAX_MB = 5; MAX_UPLOAD_MB = 15; MAX_PATROL_PHOTOS = 6
ALLOWED_EXT = {"jpg","jpeg","png","webp"}
VERSION = "6.10.0"
DEFAULT_ADMIN_ID = os.environ.get("DEFAULT_ADMIN_ID","SA00001")
DEFAULT_ADMIN_PASSWORD = os.environ.get("DEFAULT_ADMIN_PASSWORD","")
PBKDF2_ITERATIONS = 390000
ROLE_PREFIX = {"super_admin":"SA","admin":"AD","koordinator":"KR","warga":"WG"}
VAPID_PUBLIC_KEY = os.environ.get("VAPID_PUBLIC_KEY","")
VAPID_PRIVATE_KEY_PATH = os.environ.get("VAPID_PRIVATE_KEY_PATH",str(BASE_DIR/"vapid_private.pem"))
VAPID_SUBJECT = os.environ.get("VAPID_SUBJECT","mailto:admin@example.com")
APP_TZ = ZoneInfo(os.environ.get("APP_TIMEZONE","Asia/Jakarta"))

LOG_DIR.mkdir(parents=True, exist_ok=True)
for _f in ["profile","ronda","laporan","qr"]:
    (UPLOAD_DIR/_f).mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    handlers=[logging.FileHandler(LOG_DIR/"app.log",encoding="utf-8"), logging.StreamHandler()],
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("siskamling")

engine = create_engine(f"sqlite:///{BASE_DIR}/ronda.db", connect_args={"check_same_thread":False})
DB = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

@sa_event.listens_for(engine,"connect")
def on_connect(conn,_):
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA cache_size=-32000")

# ── MODELS ────────────────────────────────────────────────
class Warga(Base):
    __tablename__ = "warga"
    id=Column(Integer,primary_key=True); nama=Column(String(100),nullable=False)
    akun_id=Column(String(7),unique=True,index=True,nullable=True)
    no_hp=Column(String(20),unique=True,index=True,nullable=False)
    password_hash=Column(String(255),nullable=True)
    auth_version=Column(Integer,default=1,nullable=False)
    tanggal_lahir=Column(String(12),nullable=False)
    grup_id=Column(Integer,default=1,index=True); role=Column(String(20),default="warga")
    foto_profil=Column(String(200)); is_active=Column(Boolean,default=True)
    catatan=Column(Text); created_at=Column(DateTime,nullable=True)

class Device(Base):
    __tablename__="devices"
    id=Column(Integer,primary_key=True); warga_id=Column(Integer,index=True)
    installation_id=Column(String(100)); last_seen=Column(DateTime,default=datetime.utcnow)

class GroupInfo(Base):
    __tablename__="group_info"
    id=Column(Integer,primary_key=True)
    grup_id=Column(Integer,unique=True,index=True)
    nama=Column(String(100)); deskripsi=Column(String(300))
    updated_at=Column(DateTime,default=datetime.utcnow)

class Checkpoint(Base):
    __tablename__="checkpoints"
    id=Column(Integer,primary_key=True); nama=Column(String(100))
    token=Column(String(50),unique=True,index=True); lokasi=Column(String(200))
    lat=Column(Float); lon=Column(Float); tipe=Column(String(20),default="patrol")
    urutan=Column(Integer,default=0,index=True); radius_meter=Column(Integer,default=30)
    is_active=Column(Boolean,default=True); created_at=Column(DateTime,default=datetime.utcnow)

class Attendance(Base):
    __tablename__="attendance"
    id=Column(Integer,primary_key=True); warga_id=Column(Integer,index=True)
    tanggal=Column(String(12),index=True)
    check_in=Column(DateTime); lat_in=Column(Float); lon_in=Column(Float); cp_in=Column(String(50))
    check_out=Column(DateTime); lat_out=Column(Float); lon_out=Column(Float); cp_out=Column(String(50))
    durasi_menit=Column(Integer)
    status=Column(String(20),default="hadir"); keterangan=Column(String(300)); manual_by=Column(Integer)

class PatrolVisit(Base):
    __tablename__="patrol_visits"
    id=Column(Integer,primary_key=True); warga_id=Column(Integer,index=True)
    grup_id=Column(Integer,index=True); cp_token=Column(String(50)); cp_nama=Column(String(100))
    timestamp=Column(DateTime,default=datetime.utcnow,index=True)
    keterangan=Column(Text); lat=Column(Float); lon=Column(Float); photo_path=Column(String(200))
    photo_paths=Column(Text,nullable=True)

class Setting(Base):
    __tablename__="settings"
    key=Column(String(50),primary_key=True); value=Column(String(500))
    label=Column(String(200)); updated_at=Column(DateTime,default=datetime.utcnow)

class AuditLog(Base):
    __tablename__="audit_log"
    id=Column(Integer,primary_key=True); warga_id=Column(Integer,index=True)
    action=Column(String(100)); detail=Column(Text); ip=Column(String(50))
    ts=Column(DateTime,default=datetime.utcnow,index=True)

class Emergency(Base):
    __tablename__="emergency"
    id=Column(Integer,primary_key=True); warga_id=Column(Integer,index=True)
    lat=Column(Float); lon=Column(Float); ket=Column(Text)
    ts=Column(DateTime,default=datetime.utcnow)
    resolved=Column(Boolean,default=False); resolved_by=Column(Integer)

class Iuran(Base):
    __tablename__="iuran"
    id=Column(Integer,primary_key=True); warga_id=Column(Integer,index=True)
    bulan=Column(Integer); tahun=Column(Integer); nominal=Column(Integer,default=0)
    tgl_bayar=Column(DateTime); bukti_path=Column(String(200)); catatan=Column(String(200))
    status=Column(String(20),default="belum")

class JadwalRonda(Base):
    __tablename__="jadwal_ronda"
    id=Column(Integer,primary_key=True); grup_id=Column(Integer,index=True)
    hari=Column(Integer,nullable=True); tanggal=Column(String(12),nullable=True)
    catatan=Column(String(200)); is_active=Column(Boolean,default=True)

class Kompensasi(Base):
    __tablename__="kompensasi"
    __table_args__=(UniqueConstraint("warga_id","tanggal",name="uq_kompensasi_warga_tanggal"),)
    id=Column(Integer,primary_key=True); warga_id=Column(Integer,index=True)
    grup_id=Column(Integer,index=True); jadwal_id=Column(Integer,nullable=True)
    tanggal=Column(String(12),index=True); hari=Column(String(20)); nominal=Column(Integer,default=25000)
    alasan=Column(String(300),default="Tidak melaksanakan jadwal ronda")
    status=Column(String(20),default="belum",index=True)
    verified_by=Column(Integer,nullable=True); verified_at=Column(DateTime,nullable=True)
    catatan=Column(String(300)); created_at=Column(DateTime,default=datetime.utcnow)

class PenggantiRonda(Base):
    __tablename__="pengganti_ronda"
    id=Column(Integer,primary_key=True); tanggal=Column(String(12),index=True)
    warga_asli_id=Column(Integer); warga_pengganti_id=Column(Integer,index=True)
    grup_id=Column(Integer); catatan=Column(String(200)); disetujui_oleh=Column(Integer)
    created_at=Column(DateTime,default=datetime.utcnow)

class ChatMessage(Base):
    __tablename__="chat_messages"
    id=Column(Integer,primary_key=True); grup_id=Column(Integer,index=True)
    warga_id=Column(Integer); tipe=Column(String(20),default="text"); pesan=Column(Text)
    timestamp=Column(DateTime,default=datetime.utcnow,index=True)
    reply_to_id=Column(Integer,nullable=True); reply_preview=Column(String(200),nullable=True)
    is_deleted=Column(Boolean,default=False); media_paths=Column(Text,nullable=True)

class ChatInvite(Base):
    __tablename__="chat_invites"
    id=Column(Integer,primary_key=True); grup_id=Column(Integer)
    dari_id=Column(Integer); ke_id=Column(Integer,index=True)
    status=Column(String(20),default="pending"); timestamp=Column(DateTime,default=datetime.utcnow)

class Notifikasi(Base):
    __tablename__="notifikasi"
    id=Column(Integer,primary_key=True)
    grup_id=Column(Integer,nullable=True,index=True); warga_id=Column(Integer,nullable=True,index=True)
    tipe=Column(String(30)); judul=Column(String(100)); pesan=Column(Text)
    source_id=Column(Integer,nullable=True,index=True)
    dibaca=Column(Boolean,default=False); timestamp=Column(DateTime,default=datetime.utcnow,index=True)

class PushSubscription(Base):
    __tablename__="push_subscriptions"
    id=Column(Integer,primary_key=True); warga_id=Column(Integer,index=True,nullable=False)
    endpoint=Column(Text,unique=True,nullable=False); p256dh=Column(Text,nullable=False); auth=Column(Text,nullable=False)
    user_agent=Column(String(300)); created_at=Column(DateTime,default=datetime.utcnow)
    last_seen=Column(DateTime,default=datetime.utcnow)

Base.metadata.create_all(bind=engine)
with engine.begin() as _conn:
    _conn.exec_driver_sql("CREATE UNIQUE INDEX IF NOT EXISTS ux_warga_akun_id_nocase ON warga(akun_id COLLATE NOCASE)")

# ── HELPERS ────────────────────────────────────────────────
def get_db():
    db=DB()
    try: yield db
    finally: db.close()

def local_now(): return datetime.now(APP_TZ)

def make_token(wid,role,grup,auth_version=1):
    return jwt.encode({"sub":str(wid),"role":role,"grup":grup,
        "av":auth_version,
        "exp":datetime.utcnow()+timedelta(hours=TOKEN_HOURS)},SECRET_KEY,algorithm=ALGORITHM)

def parse_token(authorization:str=Header(None))->str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401,"Token tidak ditemukan. Silakan login ulang.")
    return authorization[7:]

def current_user(token:str=Depends(parse_token),db:Session=Depends(get_db))->Warga:
    try: payload=jwt.decode(token,SECRET_KEY,algorithms=[ALGORITHM])
    except JWTError: raise HTTPException(401,"Sesi habis. Silakan login ulang.")
    w=db.query(Warga).filter(Warga.id==int(payload["sub"]),Warga.is_active==True).first()
    if not w: raise HTTPException(401,"Akun tidak aktif.")
    if int(payload.get("av",0))!=int(w.auth_version or 1):
        raise HTTPException(401,"Sesi sudah dicabut. Silakan login ulang.")
    return w

def get_role_from_token(authorization:str)->str:
    if not authorization or not authorization.startswith("Bearer "): return "warga"
    try:
        payload=jwt.decode(authorization[7:],SECRET_KEY,algorithms=[ALGORITHM])
        return payload.get("role","warga")
    except: return "warga"

def require_admin(u:Warga=Depends(current_user))->Warga:
    if u.role not in ("admin","super_admin"): raise HTTPException(403,"Hanya Admin.")
    return u

def require_chat_manager(u:Warga=Depends(current_user))->Warga:
    if u.role not in ("koordinator","admin","super_admin"):
        raise HTTPException(403,"Hanya Koordinator atau Admin yang dapat mengundang warga.")
    return u

def require_manager(u:Warga=Depends(current_user))->Warga:
    if u.role not in ("koordinator","admin","super_admin"):
        raise HTTPException(403,"Hanya Koordinator atau Admin.")
    return u

def find_warga(db:Session,identifier:str):
    ident=(identifier or "").strip()
    return db.query(Warga).filter(or_(Warga.akun_id==ident.upper(),Warga.no_hp==ident)).first()

def validate_akun_id(value:str,role:str=None):
    value=(value or "").strip().upper()
    if not re.fullmatch(r"(?:SA|AD|KR|WG)\d{5}",value):
        raise HTTPException(400,"Format ID harus SA/AD/KR/WG diikuti 5 digit, contoh WG00001.")
    expected=ROLE_PREFIX.get(role) if role else None
    if expected and not value.startswith(expected):
        raise HTTPException(400,f"ID untuk role {role} harus diawali {expected}.")
    return value

def validate_password(value:str):
    if len(value or "")<6: raise HTTPException(400,"Password minimal 6 karakter.")
    if len(value)>72: raise HTTPException(400,"Password maksimal 72 karakter.")
    if not re.search(r"[A-Za-z]",value) or not re.search(r"\d",value):
        raise HTTPException(400,"Password wajib mengandung minimal satu huruf dan satu angka.")
    return value

def hash_password(value:str):
    validate_password(value)
    salt=secrets.token_bytes(16)
    digest=hashlib.pbkdf2_hmac("sha256",value.encode("utf-8"),salt,PBKDF2_ITERATIONS)
    enc=lambda b: base64.urlsafe_b64encode(b).decode("ascii").rstrip("=")
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${enc(salt)}${enc(digest)}"

def verify_password(value:str,stored:str):
    if not value or not stored: return False
    if stored.startswith("pbkdf2_sha256$"):
        try:
            _,rounds,salt_s,digest_s=stored.split("$",3)
            dec=lambda s: base64.urlsafe_b64decode(s+"="*((4-len(s)%4)%4))
            actual=hashlib.pbkdf2_hmac("sha256",value.encode("utf-8"),dec(salt_s),int(rounds))
            return hmac.compare_digest(actual,dec(digest_s))
        except (ValueError,TypeError): return False
    if stored.startswith(("$2a$","$2b$","$2y$")):
        try:
            import bcrypt
            raw=value.encode("utf-8")
            return len(raw)<=72 and bcrypt.checkpw(raw,stored.encode("utf-8"))
        except Exception: return False
    return False

def next_akun_id(db:Session,role:str="warga",exclude_id:int=None):
    prefix=ROLE_PREFIX.get(role,ROLE_PREFIX["warga"])
    q=db.query(Warga.akun_id).filter(Warga.akun_id!=None)
    if exclude_id is not None: q=q.filter(Warga.id!=exclude_id)
    used=set()
    for (value,) in q.all():
        value=(value or "").upper()
        if re.fullmatch(fr"{prefix}\d{{5}}",value): used.add(int(value[-5:]))
    for n in range(1,100000):
        if n not in used: return f"{prefix}{n:05d}"
    raise HTTPException(500,f"Nomor ID untuk role {role} sudah habis.")

def ensure_warga_defaults(w:Warga,db:Session):
    """Lengkapi kolom yang mungkin kosong karena input langsung melalui SQLite Web."""
    changed=False
    if not w.role: w.role="warga"; changed=True
    if not w.akun_id: w.akun_id=next_akun_id(db,w.role,w.id); changed=True
    else:
        normalized=validate_akun_id(w.akun_id,w.role)
        duplicate=db.query(Warga).filter(func.upper(Warga.akun_id)==normalized,Warga.id!=w.id).first()
        if duplicate: raise HTTPException(400,f"ID {normalized} sudah digunakan akun lain.")
        if w.akun_id!=normalized: w.akun_id=normalized; changed=True
    if w.created_at is None: w.created_at=datetime.utcnow(); changed=True
    if w.auth_version is None: w.auth_version=1; changed=True
    if w.grup_id is None: w.grup_id=1; changed=True
    if w.is_active is None: w.is_active=True; changed=True
    return changed

def validate_file(f:UploadFile):
    if not f or not f.filename: return
    ext=f.filename.rsplit(".",1)[-1].lower() if "." in f.filename else ""
    if ext not in ALLOWED_EXT: raise HTTPException(400,f"Format tidak didukung: {', '.join(ALLOWED_EXT)}")

def save_file(content:bytes,folder:str,prefix:str,ext:str)->str:
    if len(content)>MAX_UPLOAD_MB*1024*1024:
        raise HTTPException(400,f"Foto sumber terlalu besar. Maks {MAX_UPLOAD_MB}MB per foto.")
    try:
        Image.MAX_IMAGE_PIXELS=40_000_000
        with Image.open(io.BytesIO(content)) as source:
            image=ImageOps.exif_transpose(source)
            image.thumbnail((1600,1600),Image.Resampling.LANCZOS)
            if image.mode in ("RGBA","LA") or (image.mode=="P" and "transparency" in image.info):
                rgba=image.convert("RGBA"); background=Image.new("RGB",rgba.size,"white")
                background.paste(rgba,mask=rgba.getchannel("A")); image=background
            elif image.mode!="RGB": image=image.convert("RGB")
            quality=78; output=io.BytesIO()
            image.save(output,format="JPEG",quality=quality,optimize=True,progressive=True)
            while output.tell()>MAX_MB*1024*1024 and quality>52:
                quality-=8; output=io.BytesIO()
                image.save(output,format="JPEG",quality=quality,optimize=True,progressive=True)
            content=output.getvalue()
    except HTTPException: raise
    except Exception:
        raise HTTPException(400,"Foto tidak valid atau rusak.")
    if len(content)>MAX_MB*1024*1024:
        raise HTTPException(400,f"Foto tetap melebihi {MAX_MB}MB setelah dikompres.")
    t=UPLOAD_DIR/folder; t.mkdir(parents=True,exist_ok=True)
    fn=f"{prefix}_{uuid.uuid4().hex[:8]}.jpg"; (t/fn).write_bytes(content); return fn

async def save_patrol_photos(photo=None,photos=None,prefix="patrol"):
    uploads=[]
    if photo and getattr(photo,"filename",None): uploads.append(photo)
    uploads.extend(p for p in (photos or []) if p and getattr(p,"filename",None))
    if len(uploads)>MAX_PATROL_PHOTOS:
        raise HTTPException(400,f"Maksimal {MAX_PATROL_PHOTOS} foto untuk satu laporan patroli.")
    saved=[]
    for item in uploads:
        validate_file(item); content=await item.read()
        ext=item.filename.rsplit(".",1)[-1].lower()
        saved.append(save_file(content,"ronda",prefix,ext))
    return saved

def json_list(raw):
    try:
        value=json.loads(raw or "[]")
        return [str(x) for x in value if x] if isinstance(value,list) else []
    except Exception: return []

def patrol_chat_text(u,cp_nama,keterangan):
    return (f"📍 LAPORAN PATROLI\n"
            f"Petugas: {u.nama} ({u.akun_id or '-'})\n"
            f"Grup: {u.grup_id}\nPos/Lokasi: {cp_nama}\n"
            f"Waktu: {local_now().strftime('%d-%m-%Y %H:%M')} WIB\n"
            f"Situasi: {keterangan[:500]}")

def parse_dt(s):
    for fmt in ["%Y-%m-%d %H:%M:%S.%f","%Y-%m-%d %H:%M:%S","%Y-%m-%dT%H:%M:%S.%f","%Y-%m-%dT%H:%M:%S"]:
        try: return datetime.strptime(s,fmt)
        except: continue
    return None

def check_time(db:Session):
    cfg={s.key:s.value for s in db.query(Setting).all()}
    if cfg.get("allow_bypass_time","false")=="true": return None,None
    now=local_now().time()
    t1s=cfg.get("jam_mulai","23:00"); t2s=cfg.get("jam_selesai","04:00")
    h1,m1=map(int,t1s.split(":")); h2,m2=map(int,t2s.split(":"))
    t1,t2=time(h1,m1),time(h2,m2); ok=(now>=t1 or now<=t2) if t1>t2 else (t1<=now<=t2)
    if not ok: raise HTTPException(403,f"DILUAR_WAKTU|Absensi hanya pukul {t1s}–{t2s}. Sekarang: {now.strftime('%H:%M')}")
    return t1s,t2s

def check_jadwal(warga:Warga,db:Session):
    cfg={s.key:s.value for s in db.query(Setting).all()}
    if cfg.get("allow_bypass_time","false")=="true" or cfg.get("jadwal_wajib","true")=="false": return
    local=local_now(); today_wd=local.weekday(); today_str=local.date().isoformat()
    jadwal=db.query(JadwalRonda).filter(JadwalRonda.grup_id==warga.grup_id,JadwalRonda.is_active==True).filter(
        or_(JadwalRonda.hari==today_wd,JadwalRonda.tanggal==today_str)).first()
    if jadwal: return
    pg=db.query(PenggantiRonda).filter(PenggantiRonda.warga_pengganti_id==warga.id,
        PenggantiRonda.tanggal==today_str).first()
    if pg: return
    HARI=["Senin","Selasa","Rabu","Kamis","Jumat","Sabtu","Minggu"]
    raise HTTPException(403,f"DILUAR_JADWAL|Grup {warga.grup_id} tidak berjadwal hari {HARI[today_wd]}. Hubungi Admin untuk mengubah jadwal.")

def haversine(lat1,lon1,lat2,lon2):
    R=6371000; dl=radians(lat2-lat1); dlo=radians(lon2-lon1)
    a=sin(dl/2)**2+cos(radians(lat1))*cos(radians(lat2))*sin(dlo/2)**2
    return R*2*atan2(sqrt(a),sqrt(1-a))

def patrol_window(db:Session):
    cfg={s.key:s.value for s in db.query(Setting).filter(Setting.key.in_(["jam_mulai","jam_selesai"])).all()}
    try:
        sh,sm=map(int,cfg.get("jam_mulai","23:00").split(":")); eh,em=map(int,cfg.get("jam_selesai","04:00").split(":"))
        start_t,end_t=time(sh,sm),time(eh,em)
    except Exception: start_t,end_t=time(23,0),time(4,0)
    now=local_now(); overnight=start_t>end_t
    duty=now.date()-timedelta(days=1) if overnight and now.time()<=end_t else now.date()
    start_local=datetime.combine(duty,start_t,tzinfo=APP_TZ)
    end_local=datetime.combine(duty+timedelta(days=1) if overnight else duty,end_t,tzinfo=APP_TZ)
    return (start_local.astimezone(timezone.utc).replace(tzinfo=None),
            end_local.astimezone(timezone.utc).replace(tzinfo=None),duty,start_local,end_local)

def patrol_checkpoints(db:Session):
    return db.query(Checkpoint).filter(Checkpoint.is_active==True,Checkpoint.tipe=="patrol").order_by(
        Checkpoint.urutan.asc(),Checkpoint.id.asc()).all()

def patrol_route_data(db:Session,grup_id:int):
    start_utc,end_utc,duty,start_local,end_local=patrol_window(db); cps=patrol_checkpoints(db)
    tokens=[c.token for c in cps]
    visits=db.query(PatrolVisit).filter(PatrolVisit.grup_id==grup_id,
        PatrolVisit.timestamp>=start_utc,PatrolVisit.timestamp<end_utc,
        PatrolVisit.cp_token.in_(tokens) if tokens else PatrolVisit.id<0).order_by(PatrolVisit.timestamp).all()
    first={}
    for visit in visits: first.setdefault(visit.cp_token,visit)
    people={w.id:w.nama for w in db.query(Warga).filter(Warga.id.in_([v.warga_id for v in first.values()])).all()} if first else {}
    completed=sum(1 for c in cps if c.token in first); next_cp=next((c for c in cps if c.token not in first),None)
    items=[]
    for index,c in enumerate(cps,1):
        visit=first.get(c.token); status="selesai" if visit else "berikutnya" if next_cp and c.id==next_cp.id else "belum"
        items.append({"id":c.id,"urutan":index,"nama":c.nama,"lokasi":c.lokasi,
            "lat":c.lat,"lon":c.lon,"status":status,
            "waktu":visit.timestamp.strftime("%H:%M") if visit else None,
            "oleh":people.get(visit.warga_id) if visit else None})
    setting=db.query(Setting).filter(Setting.key=="patrol_wajib_berurutan").first()
    enforced=not setting or (setting.value or "true").lower()=="true"
    return {"tanggal":duty.isoformat(),"mulai":start_local.strftime("%d-%m-%Y %H:%M"),
        "selesai_jam":end_local.strftime("%d-%m-%Y %H:%M"),"items":items,"completed":completed,"total":len(cps),
        "percent":round(completed*100/len(cps)) if cps else 0,"complete":bool(cps) and completed==len(cps),
        "next_id":next_cp.id if next_cp else None,"next_name":next_cp.nama if next_cp else None,"enforced":enforced}

def enforce_patrol_order(db:Session,u:Warga,cp:Checkpoint):
    route=patrol_route_data(db,u.grup_id)
    if not route["enforced"] or route["complete"] or not route["items"]: return route
    if cp.id!=route["next_id"]:
        item=next((x for x in route["items"] if x["id"]==cp.id),None)
        if item and item["status"]=="selesai":
            raise HTTPException(409,f"CHECKPOINT_SELESAI|{cp.nama} sudah dikunjungi. Tujuan berikutnya: {route['next_name']}.")
        raise HTTPException(409,f"RUTE_BERURUTAN|Selesaikan {route['next_name']} terlebih dahulu sebelum {cp.nama}.")
    return route

def push_target_url(tipe):
    return "/?push=chat" if tipe=="chat" else "/?push=kompensasi" if tipe=="kompensasi" else "/?push=sos" if tipe=="sos" else "/"

def send_web_push(db,tipe,judul,pesan,grup_id=None,warga_id=None,source_id=None,exclude_id=None):
    if tipe not in ("sos","chat","kompensasi") or not VAPID_PUBLIC_KEY or not Path(VAPID_PRIVATE_KEY_PATH).exists(): return 0
    q=db.query(PushSubscription)
    if warga_id is not None: q=q.filter(PushSubscription.warga_id==warga_id)
    elif grup_id is not None:
        q=q.join(Warga,Warga.id==PushSubscription.warga_id).filter(Warga.grup_id==grup_id,Warga.is_active==True)
    else: q=q.join(Warga,Warga.id==PushSubscription.warga_id).filter(Warga.is_active==True)
    if exclude_id is not None: q=q.filter(PushSubscription.warga_id!=exclude_id)
    payload=json.dumps({"title":judul[:100],"body":pesan[:220],"type":tipe,
        "tag":f"{tipe}-{source_id}" if source_id is not None else tipe,
        "icon":"/static/icon.svg","data":{"url":push_target_url(tipe)}},ensure_ascii=False)
    subscriptions=[{"id":s.id,"endpoint":s.endpoint,"p256dh":s.p256dh,"auth":s.auth} for s in q.all()]
    if not subscriptions: return 0
    def deliver():
        expired=[]
        for sub in subscriptions:
            try: webpush(subscription_info={"endpoint":sub["endpoint"],"keys":{"p256dh":sub["p256dh"],"auth":sub["auth"]}},
                data=payload,vapid_private_key=VAPID_PRIVATE_KEY_PATH,vapid_claims={"sub":VAPID_SUBJECT},ttl=86400,timeout=6)
            except WebPushException as exc:
                response=getattr(exc,"response",None); status=getattr(response,"status_code",getattr(response,"status",None))
                if status in (404,410): expired.append(sub["id"])
                else: logger.warning(f"Web Push gagal ({status or 'network'}): {exc}")
            except Exception as exc: logger.warning(f"Web Push gagal: {exc}")
        if expired:
            cleanup=DB()
            try: cleanup.query(PushSubscription).filter(PushSubscription.id.in_(expired)).delete(synchronize_session=False); cleanup.commit()
            except Exception: cleanup.rollback()
            finally: cleanup.close()
    threading.Thread(target=deliver,daemon=True,name=f"push-{tipe}").start()
    return len(subscriptions)

def close_web_push_tag(db,tag):
    if not VAPID_PUBLIC_KEY or not Path(VAPID_PRIVATE_KEY_PATH).exists(): return
    payload=json.dumps({"action":"close","tag":tag})
    subscriptions=[{"endpoint":s.endpoint,"p256dh":s.p256dh,"auth":s.auth} for s in db.query(PushSubscription).all()]
    def deliver_close():
        for sub in subscriptions:
            try: webpush(subscription_info={"endpoint":sub["endpoint"],"keys":{"p256dh":sub["p256dh"],"auth":sub["auth"]}},
                data=payload,vapid_private_key=VAPID_PRIVATE_KEY_PATH,vapid_claims={"sub":VAPID_SUBJECT},ttl=60,timeout=5)
            except Exception: pass
    if subscriptions: threading.Thread(target=deliver_close,daemon=True,name="push-close").start()

def push_notif(db,tipe,judul,pesan,grup_id=None,warga_id=None,source_id=None,exclude_id=None):
    try:
        db.add(Notifikasi(grup_id=grup_id,warga_id=warga_id,tipe=tipe,judul=judul[:100],pesan=pesan[:300],source_id=source_id))
        send_web_push(db,tipe,judul,pesan,grup_id,warga_id,source_id,exclude_id)
    except Exception as exc: logger.warning(f"Notifikasi gagal: {exc}")

def push_all_users(db,tipe,judul,pesan,exclude_id=None,source_id=None):
    """Notifikasi personal agar status baca/hapus satu warga tidak memengaruhi warga lain."""
    for (wid,) in db.query(Warga.id).filter(Warga.is_active==True).all():
        if exclude_id is None or wid!=exclude_id:
            db.add(Notifikasi(warga_id=wid,tipe=tipe,judul=judul[:100],pesan=pesan[:300],source_id=source_id))
    send_web_push(db,tipe,judul,pesan,source_id=source_id,exclude_id=exclude_id)

def audit(db,wid,action,detail="",ip=""):
    try: db.add(AuditLog(warga_id=wid,action=action,detail=detail[:500],ip=ip))
    except: pass

def warga_dict(w,include_foto=True):
    return {"id":w.id,"akun_id":w.akun_id,"nama":w.nama,"no_hp":w.no_hp,"tanggal_lahir":w.tanggal_lahir,
            "grup_id":w.grup_id,"role":w.role,"is_active":w.is_active,
            "foto":w.foto_profil if include_foto else None,"catatan":w.catatan,
            "password_set":bool(w.password_hash),
            "created_at":w.created_at.strftime("%Y-%m-%d") if w.created_at else None}

def group_nama(db,grup_id):
    info=db.query(GroupInfo).filter(GroupInfo.grup_id==grup_id).first()
    return info.nama if info else f"Grup {grup_id}"

# Dataset yang boleh dicadangkan/dipulihkan oleh admin. Kolom perangkat dan
# password berupa hash, bukan password asli. File ekspor tetap harus disimpan aman.
DATASET_CONFIG={
    "warga":{"label":"Data Warga","model":Warga,
        "fields":["id","nama","akun_id","no_hp","password_hash","auth_version","tanggal_lahir","grup_id","role","foto_profil","is_active","catatan","created_at"],
        "keys":[("akun_id",),("no_hp",),("id",)]},
    "grup":{"label":"Grup Ronda","model":GroupInfo,
        "fields":["id","grup_id","nama","deskripsi","updated_at"],"keys":[("grup_id",),("id",)]},
    "checkpoint":{"label":"Checkpoint","model":Checkpoint,
        "fields":["id","nama","token","lokasi","lat","lon","tipe","urutan","radius_meter","is_active","created_at"],"keys":[("token",),("id",)]},
    "jadwal":{"label":"Jadwal Ronda","model":JadwalRonda,
        "fields":["id","grup_id","hari","tanggal","catatan","is_active"],"keys":[("id",)]},
    "kompensasi":{"label":"Tagihan Kompensasi","model":Kompensasi,
        "fields":["id","warga_id","grup_id","jadwal_id","tanggal","hari","nominal","alasan","status","verified_by","verified_at","catatan","created_at"],
        "keys":[("warga_id","tanggal"),("id",)]},
    "absensi":{"label":"Absensi","model":Attendance,
        "fields":["id","warga_id","tanggal","check_in","lat_in","lon_in","cp_in","check_out","lat_out","lon_out","cp_out","durasi_menit","status","keterangan","manual_by"],
        "keys":[("warga_id","tanggal"),("id",)]},
    "patroli":{"label":"Riwayat Patroli","model":PatrolVisit,
        "fields":["id","warga_id","grup_id","cp_token","cp_nama","timestamp","keterangan","lat","lon","photo_path","photo_paths"],"keys":[("id",)]},
    "sos":{"label":"SOS","model":Emergency,
        "fields":["id","warga_id","lat","lon","ket","ts","resolved","resolved_by"],"keys":[("id",)]},
    "iuran":{"label":"Iuran","model":Iuran,
        "fields":["id","warga_id","bulan","tahun","nominal","tgl_bayar","bukti_path","catatan","status"],
        "keys":[("warga_id","bulan","tahun"),("id",)]},
    "pengganti":{"label":"Pengganti Ronda","model":PenggantiRonda,
        "fields":["id","tanggal","warga_asli_id","warga_pengganti_id","grup_id","catatan","disetujui_oleh","created_at"],"keys":[("id",)]},
    "chat":{"label":"Chat","model":ChatMessage,
        "fields":["id","grup_id","warga_id","tipe","pesan","timestamp","reply_to_id","reply_preview","is_deleted","media_paths"],"keys":[("id",)]},
    "undangan_chat":{"label":"Undangan Chat","model":ChatInvite,
        "fields":["id","grup_id","dari_id","ke_id","status","timestamp"],"keys":[("id",)]},
    "notifikasi":{"label":"Notifikasi","model":Notifikasi,
        "fields":["id","grup_id","warga_id","tipe","judul","pesan","source_id","dibaca","timestamp"],"keys":[("id",)]},
    "push":{"label":"Langganan Web Push","model":PushSubscription,
        "fields":["id","warga_id","endpoint","p256dh","auth","user_agent","created_at","last_seen"],"keys":[("endpoint",),("id",)]},
    "perangkat":{"label":"Perangkat Terdaftar","model":Device,
        "fields":["id","warga_id","installation_id","last_seen"],"keys":[("id",)]},
    "pengaturan":{"label":"Pengaturan","model":Setting,
        "fields":["key","value","label","updated_at"],"keys":[("key",)]},
    "audit":{"label":"Audit Log","model":AuditLog,
        "fields":["id","warga_id","action","detail","ip","ts"],"keys":[("id",)]},
}
DATASET_ORDER=list(DATASET_CONFIG)
IMPORT_FIELD_ALIASES={
    "id warga":"akun_id","id_warga":"akun_id","nama lengkap":"nama","nama_warga":"nama",
    "nomor hp":"no_hp","no hp":"no_hp","no. hp":"no_hp","nomor handphone":"no_hp",
    "tanggal lahir":"tanggal_lahir","grup":"grup_id","nomor grup":"grup_id",
    "status aktif":"is_active","catatan warga":"catatan",
}

def selected_datasets(raw):
    names=[x.strip().lower() for x in (raw or "all").split(",") if x.strip()]
    if not names or "all" in names: return DATASET_ORDER.copy()
    bad=[x for x in names if x not in DATASET_CONFIG]
    if bad: raise HTTPException(400,f"Dataset tidak dikenal: {', '.join(bad)}")
    return list(dict.fromkeys(names))

def export_cell(value):
    if isinstance(value,(datetime,date,time)): return value.isoformat()
    return value

def normalize_header(value):
    key=re.sub(r"\s+"," ",str(value or "").strip().lower().replace("-"," "))
    return IMPORT_FIELD_ALIASES.get(key,key.replace(" ","_"))

def excel_rows_by_field(ws):
    """Baca sheet normal; kompatibel juga dengan Excel lama yang tersimpan satu kolom CSV."""
    iterator=ws.iter_rows(values_only=True); raw_headers=next(iterator,None)
    if not raw_headers: return []
    populated=[value for value in raw_headers if value not in (None,"")]
    if len(populated)==1 and isinstance(populated[0],str):
        header_text=populated[0]
        delimiter=";" if header_text.count(";")>header_text.count(",") else ","
        if delimiter in header_text:
            headers=[normalize_header(value) for value in next(csv.reader([header_text],delimiter=delimiter))]
            result=[]
            for row in iterator:
                text=str(next((value for value in row if value not in (None,"")),""))
                if not text: continue
                values=next(csv.reader([text],delimiter=delimiter))
                result.append({headers[i]:value for i,value in enumerate(values) if i<len(headers)})
            return result
    headers=[normalize_header(value) for value in raw_headers]
    return [{headers[i]:value for i,value in enumerate(row) if i<len(headers)}
            for row in iterator if any(value not in (None,"") for value in row)]

def import_cell(model,field,value):
    if value is None or value=="": return None
    if field=="akun_id":
        return str(value).strip().upper()
    if field=="no_hp":
        return str(int(value) if isinstance(value,float) and value.is_integer() else value).strip()
    if field=="tanggal_lahir" and isinstance(value,(datetime,date)):
        return value.strftime("%d-%m-%Y")
    col=model.__table__.columns.get(field)
    if col is None: return value
    if isinstance(col.type,Boolean):
        if isinstance(value,bool): return value
        return str(value).strip().lower() in ("1","true","ya","yes","aktif","y")
    if isinstance(col.type,Integer): return int(float(value))
    if isinstance(col.type,Float): return float(value)
    if isinstance(col.type,DateTime):
        if isinstance(value,datetime): return value
        if isinstance(value,date): return datetime.combine(value,time.min)
        parsed=parse_dt(str(value).replace("T"," "))
        if not parsed:
            try: parsed=datetime.fromisoformat(str(value))
            except ValueError: raise ValueError(f"Format waktu {field} tidak valid")
        return parsed
    return str(value).strip()

def find_import_target(db,cfg,data):
    model=cfg["model"]
    for keyset in cfg["keys"]:
        if all(data.get(k) not in (None,"") for k in keyset):
            q=db.query(model)
            for key in keyset:
                if model is Warga and key=="akun_id": q=q.filter(func.upper(Warga.akun_id)==str(data[key]).upper())
                else: q=q.filter(getattr(model,key)==data[key])
            found=q.first()
            if found: return found
    return None

def import_dataset_row(db,name,row,actor,mode="merge"):
    cfg=DATASET_CONFIG[name]; model=cfg["model"]
    normalized={normalize_header(k):v for k,v in dict(row).items()}
    data={}
    for field in cfg["fields"]:
        if field in normalized and normalized[field] not in (None,""):
            data[field]=import_cell(model,field,normalized[field])
    if name=="warga":
        if "akun_id" in data: validate_akun_id(data["akun_id"])
        if data.get("role") not in (None,"warga","koordinator","admin","super_admin"):
            raise ValueError("Role tidak valid")
        if data.get("role")=="super_admin" and actor.role!="super_admin":
            raise ValueError("Hanya Super Admin dapat mengimpor role super_admin")
        if data.get("password_hash") and not str(data["password_hash"]).startswith(("pbkdf2_sha256$","$2a$","$2b$","$2y$")):
            raise ValueError("Format password_hash tidak didukung")
    target=find_import_target(db,cfg,data)
    if target and mode=="new": return "skipped"
    if not target:
        if name=="warga":
            for req in ("nama","no_hp","tanggal_lahir"):
                if not data.get(req): raise ValueError(f"Kolom {req} wajib untuk warga baru")
            data.setdefault("grup_id",1)
            data.setdefault("role","warga"); data.setdefault("is_active",True)
        target=model(); db.add(target); state="created"
    else: state="updated"
    if name=="warga" and target.id and data.get("role") and data["role"]!=target.role and not data.get("akun_id") and target.akun_id:
        data["akun_id"]=next_akun_id(db,data["role"],target.id)
    if name=="warga" and data.get("akun_id"):
        validate_akun_id(data["akun_id"],data.get("role") or getattr(target,"role",None) or "warga")
    for field,value in data.items():
        if field in cfg["fields"]: setattr(target,field,value)
    return state

def sync_kompensasi(db:Session,window_days=62):
    """Buat tagihan untuk jadwal lewat; tidak menagih sebelum fitur/warga aktif."""
    settings={s.key:s.value for s in db.query(Setting).all()}
    if settings.get("kompensasi_aktif","true").lower()!="true": return {"created":0,"cancelled":0}
    today=local_now().date(); start_default=today-timedelta(days=window_days)
    try: feature_start=date.fromisoformat(settings.get("kompensasi_mulai",today.isoformat()))
    except ValueError: feature_start=today
    start=max(start_default,feature_start); end=today-timedelta(days=1)
    if start>end: return {"created":0,"cancelled":0}
    try: nominal=max(0,int(settings.get("nominal_kompensasi","25000")))
    except ValueError: nominal=25000
    HARI=["Senin","Selasa","Rabu","Kamis","Jumat","Sabtu","Minggu"]
    schedules=db.query(JadwalRonda).filter(JadwalRonda.is_active==True).all(); created=cancelled=0
    scheduled={}
    for j in schedules:
        dates=[]
        if j.tanggal:
            try:
                special=date.fromisoformat(j.tanggal)
                if start<=special<=end: dates=[special]
            except ValueError: pass
        elif j.hari is not None and 0<=j.hari<=6:
            cursor=start
            while cursor<=end:
                if cursor.weekday()==j.hari: dates.append(cursor)
                cursor+=timedelta(days=1)
        for duty_date in dates: scheduled.setdefault((j.grup_id,duty_date.isoformat()),j)
    for (gid,tanggal),jadwal in scheduled.items():
        duty_date=date.fromisoformat(tanggal)
        residents=db.query(Warga).filter(Warga.grup_id==gid,Warga.is_active==True).all()
        for warga in residents:
            # Data SQLite Web yang belum pernah diaktifkan (created_at kosong) belum ditagih.
            if not warga.password_hash or warga.created_at is None or warga.created_at.date()>duty_date: continue
            attendance=db.query(Attendance).filter(Attendance.warga_id==warga.id,Attendance.tanggal==tanggal).order_by(Attendance.id.desc()).first()
            exempt=bool(attendance and (attendance.status or "hadir") in ("hadir","izin","sakit","lainnya"))
            bill=db.query(Kompensasi).filter(Kompensasi.warga_id==warga.id,Kompensasi.tanggal==tanggal).first()
            if exempt:
                if bill and bill.status=="belum":
                    bill.status="dibatalkan"; bill.verified_at=datetime.utcnow()
                    bill.catatan="Dibatalkan otomatis karena absensi/izin telah dicatat."; cancelled+=1
                    db.query(Notifikasi).filter(Notifikasi.tipe=="kompensasi",Notifikasi.source_id==bill.id).delete(synchronize_session=False)
                continue
            if bill:
                if bill.status=="dibatalkan" and bill.verified_by is None and (bill.catatan or "").startswith("Dibatalkan otomatis"):
                    bill.status="belum"; bill.verified_at=None; bill.catatan=None
                    push_notif(db,"kompensasi","💳 Tagihan Kompensasi",
                        f"Status absensi {tanggal} dikoreksi menjadi alpa. Tagihan Rp{bill.nominal:,} aktif kembali.",warga_id=warga.id,source_id=bill.id)
                continue
            bill=Kompensasi(warga_id=warga.id,grup_id=gid,jadwal_id=jadwal.id,tanggal=tanggal,
                hari=HARI[duty_date.weekday()],nominal=nominal,
                alasan="Tidak melaksanakan jadwal ronda" if not attendance else f"Status absensi: {attendance.status}")
            db.add(bill); db.flush(); created+=1
            push_notif(db,"kompensasi","💳 Tagihan Kompensasi",
                f"Jadwal {bill.hari}, {tanggal} tidak tercatat dilakukan. Tagihan Rp{nominal:,}.",warga_id=warga.id,source_id=bill.id)
            managers=db.query(Warga).filter(Warga.is_active==True,
                or_(Warga.role.in_(["admin","super_admin"]),and_(Warga.role=="koordinator",Warga.grup_id==gid))).all()
            for manager in managers:
                push_notif(db,"kompensasi",f"💳 Kompensasi: {warga.nama}",
                    f"Grup {gid} · {bill.hari}, {tanggal} · Rp{nominal:,}",warga_id=manager.id,source_id=bill.id)
    return {"created":created,"cancelled":cancelled}

def seed():
    db=DB()
    try:
        existing_keys={s.key for s in db.query(Setting).all()} if db.query(Setting).first() else set()
        ALL_SETTINGS=[
            ("jam_mulai","23:00","Jam Mulai Ronda"),("jam_selesai","04:00","Jam Selesai Ronda"),
            ("nama_kampung","Siskamling RT/RW","Nama Lingkungan"),("nominal_iuran","50000","Iuran Bulanan (Rp)"),
            ("kompensasi_aktif","true","Aktifkan Tagihan Kompensasi"),
            ("nominal_kompensasi","25000","Nominal Kompensasi Tidak Ronda (Rp)"),
            ("kompensasi_mulai",date.today().isoformat(),"Mulai Perhitungan Kompensasi"),
            ("patrol_wajib_berurutan","true","Wajib Patroli Sesuai Urutan Checkpoint"),
            ("radius_checkpoint_meter","30","Radius Default Checkpoint Patroli (meter)"),
            ("retensi_foto_hari","7","Retensi Foto Patroli di Server"),
            ("allow_bypass_time","false","Izinkan Absen di Luar Jam"),("jadwal_wajib","true","Wajib Sesuai Jadwal Grup"),
            ("max_grup","6","Jumlah Grup Ronda"),("koordinat_lat","-6.2088","Koordinat Pusat Lat"),
            ("koordinat_lon","106.8456","Koordinat Pusat Lon"),("versi","6.10.0","Versi Aplikasi"),
        ]
        for k,v,l in ALL_SETTINGS:
            if k not in existing_keys: db.add(Setting(key=k,value=v,label=l))
        if not db.query(Checkpoint).first():
            db.add_all([
                Checkpoint(nama="Pos Masuk Utama",token="QR-IN",tipe="checkin",lokasi="Pintu Masuk RT"),
                Checkpoint(nama="Pos Keluar Utama",token="QR-OUT",tipe="checkout",lokasi="Pintu Keluar RT"),
                Checkpoint(nama="Patroli Pos Alpha",token="POS-A",tipe="patrol",lokasi="Pojok Utara",lat=-6.2080,lon=106.8450,urutan=1,radius_meter=30),
                Checkpoint(nama="Patroli Pos Bravo",token="POS-B",tipe="patrol",lokasi="Pojok Selatan",lat=-6.2100,lon=106.8470,urutan=2,radius_meter=30),
                Checkpoint(nama="Patroli Pos Charlie",token="POS-C",tipe="patrol",lokasi="Jalan Tengah",lat=-6.2090,lon=106.8460,urutan=3,radius_meter=30),
                Checkpoint(nama="Patroli Pos Delta",token="POS-D",tipe="patrol",lokasi="Ujung Barat",lat=-6.2070,lon=106.8440,urutan=4,radius_meter=30),
            ])
        default_admin=db.query(Warga).filter(Warga.role=="super_admin",Warga.no_hp=="0000").first()
        if not default_admin:
            id_owner=db.query(Warga).filter(Warga.akun_id==DEFAULT_ADMIN_ID).first()
            if id_owner:
                logger.warning("ID SA00001 sudah dipakai; akun tersebut dipertahankan sebagai Super Admin default.")
                default_admin=id_owner; default_admin.role="super_admin"
            else:
                hp="0000" if not db.query(Warga).filter(Warga.no_hp=="0000").first() else "ADMIN00001"
                if not DEFAULT_ADMIN_PASSWORD:
                    raise RuntimeError("DEFAULT_ADMIN_PASSWORD belum diatur. Jalankan melalui siskamling.sh atau isi .env.")
                default_admin=Warga(nama="Super Admin",akun_id=DEFAULT_ADMIN_ID,no_hp=hp,tanggal_lahir="01-01-2000",
                    password_hash=hash_password(DEFAULT_ADMIN_PASSWORD),role="super_admin",grup_id=0,
                    catatan="Akun Super Admin bootstrap. Segera ganti password setelah login.")
                db.add(default_admin)
        else:
            id_owner=db.query(Warga).filter(Warga.akun_id==DEFAULT_ADMIN_ID,Warga.id!=default_admin.id).first()
            if not id_owner: default_admin.akun_id=DEFAULT_ADMIN_ID
        if default_admin and not default_admin.password_hash:
            if not DEFAULT_ADMIN_PASSWORD:
                raise RuntimeError("DEFAULT_ADMIN_PASSWORD belum diatur. Jalankan melalui siskamling.sh atau isi .env.")
            default_admin.password_hash=hash_password(DEFAULT_ADMIN_PASSWORD)
        if default_admin and default_admin.created_at is None: default_admin.created_at=datetime.utcnow()
        db.commit(); logger.info("Seed OK.")
    except Exception as e: logger.error(f"Seed: {e}"); db.rollback()
    finally: db.close()

seed()

app=FastAPI(title="Siskamling Digital API",version=VERSION,docs_url="/api/docs",redoc_url="/api/redoc")
_cors_origins=[x.strip() for x in os.environ.get("CORS_ORIGINS","").split(",") if x.strip()]
if _cors_origins:
    app.add_middleware(CORSMiddleware,allow_origins=_cors_origins,allow_credentials=True,allow_methods=["*"],allow_headers=["*"])
_sd=BASE_DIR/"static"
if _sd.exists(): app.mount("/static",StaticFiles(directory=str(_sd)),name="static")
_pd=UPLOAD_DIR/"profile"
if _pd.exists(): app.mount("/uploads/profile",StaticFiles(directory=str(_pd)),name="profile")
_rd=UPLOAD_DIR/"ronda"
if _rd.exists(): app.mount("/uploads/ronda",StaticFiles(directory=str(_rd)),name="ronda")

def cleanup_expired_patrol_photos(db:Session):
    """Hapus hanya salinan foto patroli di server; laporan teks dan foto profil dipertahankan."""
    setting=db.query(Setting).filter(Setting.key=="retensi_foto_hari").first()
    raw=(setting.value if setting else "7").strip().lower()
    if raw=="manual": return {"mode":"manual","visits":0,"chats":0,"files":0}
    try: days=int(raw)
    except Exception: days=7
    if days not in (3,7,14): days=7
    cutoff=datetime.utcnow()-timedelta(days=days); filenames=set(); visits=0; chats=0
    for visit in db.query(PatrolVisit).filter(PatrolVisit.timestamp<cutoff).all():
        names=json_list(visit.photo_paths)
        if visit.photo_path: names.append(visit.photo_path)
        names={Path(name).name for name in names if name}
        if names:
            filenames.update(names); visit.photo_path=None; visit.photo_paths="[]"; visits+=1
    for message in db.query(ChatMessage).filter(ChatMessage.tipe=="patrol",ChatMessage.timestamp<cutoff).all():
        names={Path(name).name for name in json_list(message.media_paths) if name}
        if names:
            filenames.update(names); message.media_paths="[]"; chats+=1
    removed=0; patrol_dir=(UPLOAD_DIR/"ronda").resolve()
    for name in filenames:
        target=(patrol_dir/Path(name).name).resolve()
        if target.parent==patrol_dir and target.is_file():
            try: target.unlink(); removed+=1
            except OSError as exc: logger.warning(f"Gagal menghapus foto patroli {target.name}: {exc}")
    # Bersihkan berkas yatim lama yang tidak lagi memiliki referensi database.
    try:
        cutoff_ts=cutoff.replace(tzinfo=timezone.utc).timestamp()
        for target in patrol_dir.glob("*.jpg"):
            if target.is_file() and target.stat().st_mtime<cutoff_ts:
                try: target.unlink(); removed+=1
                except OSError as exc: logger.warning(f"Gagal menghapus foto yatim {target.name}: {exc}")
    except OSError as exc: logger.warning(f"Pembersihan folder foto patroli gagal: {exc}")
    return {"mode":str(days),"visits":visits,"chats":chats,"files":removed}

def compensation_scheduler():
    while True:
        scheduler_db=DB()
        try:
            result=sync_kompensasi(scheduler_db)
            photo_result=cleanup_expired_patrol_photos(scheduler_db)
            scheduler_db.commit()
            if result["created"] or result["cancelled"]: logger.info(f"Scheduler kompensasi: {result}")
            if photo_result["files"]: logger.info(f"Pembersihan foto patroli: {photo_result}")
        except Exception as exc:
            scheduler_db.rollback(); logger.error(f"Scheduler kompensasi gagal: {exc}")
        finally: scheduler_db.close()
        time_module.sleep(900)

@app.on_event("startup")
def start_scheduler():
    threading.Thread(target=compensation_scheduler,daemon=True,name="kompensasi-scheduler").start()

@app.get("/")
def ui(): return FileResponse(str(BASE_DIR/"index.html"))

@app.get("/health")
def health(db:Session=Depends(get_db)):
    return {"status":"ok","version":VERSION,"warga":db.query(Warga).filter(Warga.is_active==True).count(),
            "time":local_now().strftime("%Y-%m-%d %H:%M:%S %Z")}

@app.get("/api/settings/public")
def pub_settings(db:Session=Depends(get_db)):
    s={r.key:r.value for r in db.query(Setting).all()}
    return {"nama_kampung":s.get("nama_kampung"),"jam_mulai":s.get("jam_mulai","23:00"),
            "jam_selesai":s.get("jam_selesai","04:00"),"jadwal_wajib":s.get("jadwal_wajib","true")}

@app.get("/api/checkpoints")
def list_cp(authorization:str=Header(None),db:Session=Depends(get_db)):
    role=get_role_from_token(authorization)
    is_privileged = role in ("admin","super_admin","koordinator")
    cps=db.query(Checkpoint).filter(Checkpoint.is_active==True).order_by(Checkpoint.tipe,Checkpoint.urutan,Checkpoint.id).all()
    return [{"id":c.id,"nama":c.nama,
             "token":c.token if is_privileged else None,
             "tipe":c.tipe,"urutan":c.urutan or 0,"lokasi":c.lokasi,"lat":c.lat,"lon":c.lon,
             "radius_meter":max(25,min(1000,c.radius_meter or 30))} for c in cps]

# ── AUTH ──────────────────────────────────────────────────
@app.post("/api/auth/activate")
async def activate(identifier:str=Form(...),password:str=Form(""),installation_id:str=Form(...),
                   tgl_lahir:str=Form(""),new_password:str=Form(""),
                   foto_profil:Optional[UploadFile]=File(None),request:Request=None,db:Session=Depends(get_db)):
    ip=request.client.host if request else "unknown"
    try:
        w=find_warga(db,identifier)
        if not w or w.is_active is False: raise HTTPException(404,"Akun tidak ditemukan atau tidak aktif.")
        ensure_warga_defaults(w,db)
        first_setup=not bool(w.password_hash)
        if first_setup:
            if not w.tanggal_lahir or w.tanggal_lahir.strip()!=tgl_lahir.strip():
                raise HTTPException(403,"Tanggal lahir tidak cocok.")
            validate_password(new_password)
            w.password_hash=hash_password(new_password)
        elif not verify_password(password,w.password_hash):
            raise HTTPException(401,"ID/No. HP atau password salah.")
        dev=db.query(Device).filter(Device.warga_id==w.id).first()
        is_ret=bool(dev and dev.installation_id==installation_id)
        if dev and not is_ret: raise HTTPException(403,"Akun terdaftar di perangkat lain. Minta Admin reset perangkat.")
        if not is_ret:
            if not foto_profil or not foto_profil.filename: raise HTTPException(400,"Foto profil wajib untuk perangkat baru.")
            validate_file(foto_profil); content=await foto_profil.read()
            ext=foto_profil.filename.rsplit(".",1)[-1].lower()
            w.foto_profil=save_file(content,"profile",f"profil_{w.id}",ext)
        elif foto_profil and foto_profil.filename:
            validate_file(foto_profil); content=await foto_profil.read()
            ext=foto_profil.filename.rsplit(".",1)[-1].lower()
            w.foto_profil=save_file(content,"profile",f"profil_{w.id}",ext)
        if not dev: db.add(Device(warga_id=w.id,installation_id=installation_id))
        else: dev.last_seen=datetime.utcnow()
        audit(db,w.id,"LOGIN",f"IP:{ip}",ip); db.commit()
        gname=group_nama(db,w.grup_id)
        return {"token":make_token(w.id,w.role,w.grup_id,w.auth_version or 1),"warga_id":w.id,"nama":w.nama,
                "akun_id":w.akun_id,
                "role":w.role,"grup_id":w.grup_id,"grup_nama":gname,
                "foto":w.foto_profil,"is_returning":is_ret,"password_created":first_setup}
    except HTTPException: raise
    except Exception as e: logger.error(f"Activate: {e}",exc_info=True); raise HTTPException(500,f"Server error: {e}")

@app.get("/api/me")
def me(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    return {"id":u.id,"akun_id":u.akun_id,"nama":u.nama,"no_hp":u.no_hp,"grup_id":u.grup_id,
            "grup_nama":group_nama(db,u.grup_id),"role":u.role,"foto":u.foto_profil}

@app.post("/api/auth/reset-device")
def reset_device(target_hp:str=Form(...),u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    t=find_warga(db,target_hp)
    if not t: raise HTTPException(404,"Warga tidak ditemukan.")
    db.query(Device).filter(Device.warga_id==t.id).delete()
    db.query(PushSubscription).filter(PushSubscription.warga_id==t.id).delete()
    t.auth_version=(t.auth_version or 1)+1
    audit(db,u.id,"RESET_DEVICE",f"{t.nama}"); db.commit()
    return {"message":f"Perangkat {t.nama} direset."}

@app.post("/api/auth/reset-password")
def reset_password(target_identifier:str=Form(...),u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    t=find_warga(db,target_identifier)
    if not t: raise HTTPException(404,"Warga tidak ditemukan.")
    t.password_hash=None
    t.auth_version=(t.auth_version or 1)+1
    db.query(PushSubscription).filter(PushSubscription.warga_id==t.id).delete()
    audit(db,u.id,"RESET_PASSWORD",f"{t.nama} ({t.akun_id})"); db.commit()
    return {"message":f"Password {t.nama} direset. Warga harus membuat password baru saat login."}

# ── ABSENSI ───────────────────────────────────────────────
@app.get("/api/attendance/today")
def today_status(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    today=date.today().isoformat()
    a=db.query(Attendance).filter(Attendance.warga_id==u.id,Attendance.tanggal==today).order_by(Attendance.id.desc()).first()
    if not a: return {"status":"belum_absen"}
    if a.status and a.status!="hadir":
        return {"status":"manual","status_absen":a.status,"keterangan":a.keterangan or ""}
    return {"status":"sudah_checkout" if a.check_out else "sudah_checkin",
            "check_in":a.check_in.strftime("%H:%M") if a.check_in else None,
            "check_out":a.check_out.strftime("%H:%M") if a.check_out else None,
            "durasi":a.durasi_menit,"cp_in":a.cp_in,"cp_out":a.cp_out}

@app.post("/api/attendance/checkin")
def check_in(qr_token:str=Form(...),lat:float=Form(...),lon:float=Form(...),
             u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    check_time(db); check_jadwal(u,db)
    cp=db.query(Checkpoint).filter(Checkpoint.token==qr_token.upper().strip(),
        Checkpoint.tipe=="checkin",Checkpoint.is_active==True).first()
    if not cp: raise HTTPException(400,f"QR_INVALID|Token '{qr_token}' bukan token Check-IN yang valid. Pastikan Anda scan QR di pos masuk yang benar.")
    today=date.today().isoformat()
    if db.query(Attendance).filter(Attendance.warga_id==u.id,Attendance.tanggal==today,Attendance.check_out==None).first():
        raise HTTPException(400,"SUDAH_CHECKIN|Anda sudah Check-IN hari ini. Silakan Check-OUT terlebih dahulu.")
    db.add(Attendance(warga_id=u.id,tanggal=today,check_in=datetime.utcnow(),lat_in=lat,lon_in=lon,cp_in=cp.token))
    push_notif(db,"checkin",f"Check-IN: {u.nama}",f"Check-IN di {cp.nama} pukul {datetime.now().strftime('%H:%M')}",grup_id=u.grup_id)
    audit(db,u.id,"CHECK_IN",f"CP:{cp.nama}"); db.commit()
    return {"message":f"Check-IN berhasil di {cp.nama}!","cp_nama":cp.nama,"waktu":datetime.now().strftime("%H:%M")}

@app.post("/api/attendance/checkout")
def check_out(qr_token:str=Form(...),lat:float=Form(...),lon:float=Form(...),
              u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    check_time(db); check_jadwal(u,db)
    cp=db.query(Checkpoint).filter(Checkpoint.token==qr_token.upper().strip(),
        Checkpoint.tipe=="checkout",Checkpoint.is_active==True).first()
    if not cp: raise HTTPException(400,f"QR_INVALID|Token '{qr_token}' bukan token Check-OUT yang valid.")
    today=date.today().isoformat()
    a=db.query(Attendance).filter(Attendance.warga_id==u.id,Attendance.tanggal==today,
        Attendance.check_out==None).order_by(Attendance.id.desc()).first()
    if not a: raise HTTPException(400,"BELUM_CHECKIN|Anda belum Check-IN hari ini. Lakukan Check-IN terlebih dahulu.")
    now=datetime.utcnow(); a.check_out=now; a.lat_out=lat; a.lon_out=lon; a.cp_out=cp.token
    a.durasi_menit=int((now-a.check_in).total_seconds()/60) if a.check_in else 0
    push_notif(db,"checkout",f"Check-OUT: {u.nama}",f"Selesai ronda {a.durasi_menit} menit",grup_id=u.grup_id)
    audit(db,u.id,"CHECK_OUT",f"CP:{cp.nama} Durasi:{a.durasi_menit}m"); db.commit()
    return {"message":f"Check-OUT berhasil! Durasi ronda: {a.durasi_menit} menit.","durasi":a.durasi_menit,"waktu":now.strftime("%H:%M")}

# ── PATROLI ───────────────────────────────────────────────
@app.get("/api/patrol/route")
def patrol_route(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    return patrol_route_data(db,u.grup_id)

@app.post("/api/patrol/submit")
async def submit_patrol(qr_token:str=Form(...),keterangan:str=Form(...),lat:float=Form(...),lon:float=Form(...),
                        photo:Optional[UploadFile]=File(None),photos:Optional[List[UploadFile]]=File(None),
                        u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    cp=db.query(Checkpoint).filter(Checkpoint.token==qr_token.upper().strip(),Checkpoint.is_active==True,
        Checkpoint.tipe=="patrol").first()
    if not cp: raise HTTPException(400,"Checkpoint patroli tidak valid atau sedang nonaktif.")
    route_before=enforce_patrol_order(db,u,cp); cp_nama=cp.nama
    photo_fns=await save_patrol_photos(photo,photos,"patrol")
    db.add(PatrolVisit(warga_id=u.id,grup_id=u.grup_id,cp_token=qr_token.upper(),cp_nama=cp_nama,
        keterangan=keterangan[:500],lat=lat,lon=lon,photo_path=photo_fns[0] if photo_fns else None,
        photo_paths=json.dumps(photo_fns)))
    chat_text=patrol_chat_text(u,cp_nama,keterangan)
    if route_before["total"]: chat_text+=f"\nProgress Rute: {min(route_before['completed']+1,route_before['total'])}/{route_before['total']} checkpoint"
    db.add(ChatMessage(grup_id=0,warga_id=u.id,tipe="patrol",pesan=chat_text,media_paths=json.dumps(photo_fns)))
    push_notif(db,"patrol",f"Patroli: {u.nama}",f"Laporan di {cp_nama}",grup_id=u.grup_id)
    push_all_users(db,"chat",f"📍 Patroli {u.nama}",f"{cp_nama} — {keterangan[:100]}",exclude_id=u.id)
    audit(db,u.id,"PATROL",f"CP:{cp_nama}"); db.commit(); route=patrol_route_data(db,u.grup_id)
    return {"message":f"Laporan patroli di {cp_nama} dikirim!","photos":len(photo_fns),"route":route}

@app.post("/api/patrol/gps")
async def patrol_gps(lat:float=Form(...),lon:float=Form(...),keterangan:str=Form(...),
                     selected_cp_id:int=Form(None),
                     photo:Optional[UploadFile]=File(None),photos:Optional[List[UploadFile]]=File(None),
                     u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    cps=patrol_checkpoints(db)
    radius_setting=db.query(Setting).filter(Setting.key=="radius_checkpoint_meter").first()
    try: fallback_radius=max(25,min(1000,int(radius_setting.value if radius_setting else 30)))
    except Exception: fallback_radius=30
    nearest=None; min_dist=float("inf"); inside=[]
    for cp in cps:
        if cp.lat is not None and cp.lon is not None:
            d=haversine(lat,lon,cp.lat,cp.lon)
            if d<min_dist: min_dist=d; nearest=cp
            cp_radius=max(25,min(1000,cp.radius_meter or fallback_radius))
            if d<=cp_radius: inside.append((d,cp,cp_radius))
    inside.sort(key=lambda item:item[0])
    known_cp=inside[0][1] if inside else None
    known_distance=inside[0][0] if inside else None
    detected_by="otomatis" if known_cp else "umum"
    if not known_cp and selected_cp_id:
        manual_cp=next((cp for cp in cps if cp.id==selected_cp_id),None)
        if not manual_cp: raise HTTPException(400,"POS_TIDAK_VALID|Pos pilihan tidak ditemukan atau sedang nonaktif.")
        cp_radius=max(25,min(1000,manual_cp.radius_meter or fallback_radius))
        if manual_cp.lat is not None and manual_cp.lon is not None:
            manual_distance=haversine(lat,lon,manual_cp.lat,manual_cp.lon)
            manual_limit=min(500,max(cp_radius*2,cp_radius+100))
            if manual_distance>manual_limit:
                raise HTTPException(400,f"POS_TERLALU_JAUH|Anda sekitar {round(manual_distance)} m dari {manual_cp.nama}. Pilih pos yang benar atau tandai ulang GPS.")
            known_distance=manual_distance
        known_cp=manual_cp; detected_by="manual"
    route_before=patrol_route_data(db,u.grup_id)
    if known_cp: route_before=enforce_patrol_order(db,u,known_cp)
    cp_token=known_cp.token if known_cp else f"GPS-{lat:.4f}"
    cp_nama=known_cp.nama if known_cp else f"Lokasi GPS ({lat:.5f},{lon:.5f})"
    photo_fns=await save_patrol_photos(photo,photos,"gps")
    db.add(PatrolVisit(warga_id=u.id,grup_id=u.grup_id,cp_token=cp_token,cp_nama=cp_nama,
        keterangan=keterangan[:500],lat=lat,lon=lon,photo_path=photo_fns[0] if photo_fns else None,
        photo_paths=json.dumps(photo_fns)))
    chat_text=patrol_chat_text(u,cp_nama,keterangan)
    if known_cp and route_before["total"]: chat_text+=f"\nProgress Rute: {min(route_before['completed']+1,route_before['total'])}/{route_before['total']} checkpoint"
    db.add(ChatMessage(grup_id=0,warga_id=u.id,tipe="patrol",pesan=chat_text,media_paths=json.dumps(photo_fns)))
    push_notif(db,"patrol",f"Patroli GPS: {u.nama}",cp_nama,grup_id=u.grup_id)
    push_all_users(db,"chat",f"📍 Patroli {u.nama}",f"{cp_nama} — {keterangan[:100]}",exclude_id=u.id)
    audit(db,u.id,"PATROL_GPS",f"GPS:{lat:.5f},{lon:.5f}"); db.commit(); route=patrol_route_data(db,u.grup_id)
    dist_info=f" (~{round(known_distance)}m dari {known_cp.nama})" if known_cp and known_distance is not None else ""
    return {"message":f"Lokasi patroli ditandai{dist_info}!","cp_nama":cp_nama,
            "distance":round(known_distance) if known_distance is not None else None,"photos":len(photo_fns),"route":route,
            "checkpoint_completed":bool(known_cp),"detected_by":detected_by}

# ── GRUP ─────────────────────────────────────────────────
@app.get("/api/group/info")
def group_info_api(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    info=db.query(GroupInfo).filter(GroupInfo.grup_id==u.grup_id).first()
    return {"grup_id":u.grup_id,"nama":info.nama if info else f"Grup {u.grup_id}",
            "deskripsi":info.deskripsi if info else ""}

@app.get("/api/group/members")
def group_members(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    members=db.query(Warga).filter(Warga.grup_id==u.grup_id,Warga.is_active==True).order_by(Warga.role.desc(),Warga.nama).all()
    today=date.today().isoformat(); today_wd=datetime.now().weekday(); result=[]
    for m in members:
        a=db.query(Attendance).filter(Attendance.warga_id==m.id,Attendance.tanggal==today).first()
        st="out" if(a and a.check_out) else("in" if a else "belum")
        result.append({"id":m.id,"nama":m.nama,"role":m.role,"foto":m.foto_profil,"status":st})
    jadwal=db.query(JadwalRonda).filter(JadwalRonda.grup_id==u.grup_id,JadwalRonda.is_active==True).filter(
        or_(JadwalRonda.hari==today_wd,JadwalRonda.tanggal==today)).first()
    info=db.query(GroupInfo).filter(GroupInfo.grup_id==u.grup_id).first()
    return {"members":result,"grup_id":u.grup_id,"grup_nama":info.nama if info else f"Grup {u.grup_id}",
            "jadwal_hari_ini":bool(jadwal),"total":len(result)}

@app.get("/api/group/schedule")
def group_schedule(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    HARI=["Senin","Selasa","Rabu","Kamis","Jumat","Sabtu","Minggu"]
    js=db.query(JadwalRonda).filter(JadwalRonda.grup_id==u.grup_id,JadwalRonda.is_active==True).order_by(JadwalRonda.hari).all()
    return [{"id":j.id,"hari":j.hari,"hari_nama":HARI[j.hari] if j.hari is not None else "Khusus","tanggal":j.tanggal,"catatan":j.catatan} for j in js]

@app.get("/api/group/history")
def group_history(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    ids=[w.id for w in db.query(Warga).filter(Warga.grup_id==u.grup_id).all()]; result=[]
    for p in db.query(PatrolVisit).filter(PatrolVisit.warga_id.in_(ids)).order_by(PatrolVisit.timestamp.desc()).limit(20).all():
        w=db.query(Warga).filter(Warga.id==p.warga_id).first()
        result.append({"waktu":p.timestamp.strftime("%Y-%m-%d %H:%M"),"nama":w.nama if w else "?",
                       "foto":w.foto_profil if w else None,"jenis":f"Patroli - {p.cp_nama}","keterangan":p.keterangan,
                       "foto_patroli":p.photo_path,"foto_patroli_list":json_list(p.photo_paths) or ([p.photo_path] if p.photo_path else [])})
    today=date.today().isoformat()
    for a in db.query(Attendance).filter(Attendance.warga_id.in_(ids),Attendance.tanggal==today).order_by(Attendance.id.desc()).all():
        w=db.query(Warga).filter(Warga.id==a.warga_id).first()
        st="Check-OUT" if a.check_out else "Check-IN"
        kt=f"Durasi {a.durasi_menit} menit" if a.durasi_menit else "Masih bertugas"
        result.append({"waktu":a.check_in.strftime("%Y-%m-%d %H:%M") if a.check_in else "-",
                       "nama":w.nama if w else "?","foto":w.foto_profil if w else None,"jenis":st,"keterangan":kt,
                       "foto_patroli":None,"foto_patroli_list":[]})
    result.sort(key=lambda x:x["waktu"],reverse=True)
    return {"data":result[:30],"grup_id":u.grup_id}

@app.get("/api/stats")
def stats(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    synced=sync_kompensasi(db)
    if synced["created"] or synced["cancelled"]: db.commit()
    today=date.today().isoformat()
    return {"total_warga":db.query(Warga).filter(Warga.is_active==True).count(),
            "absen_hari_ini":db.query(Attendance).filter(Attendance.tanggal==today).count(),
            "patroli_hari_ini":db.query(PatrolVisit).filter(func.date(PatrolVisit.timestamp)==today).count(),
            "emergency_aktif":db.query(Emergency).filter(Emergency.resolved==False).count(),
            "kompensasi_belum":db.query(Kompensasi).filter(Kompensasi.warga_id==u.id,Kompensasi.status=="belum").count()}

# ── KOMPENSASI ────────────────────────────────────────────
def kompensasi_dict(k,warga,db):
    verifier=db.query(Warga).filter(Warga.id==k.verified_by).first() if k.verified_by else None
    return {"id":k.id,"warga_id":k.warga_id,"akun_id":warga.akun_id if warga else None,
        "nama":warga.nama if warga else "?","no_hp":warga.no_hp if warga else "",
        "grup_id":k.grup_id,"jadwal_id":k.jadwal_id,"tanggal":k.tanggal,"hari":k.hari,
        "nominal":k.nominal or 0,"alasan":k.alasan,"status":k.status,"catatan":k.catatan,
        "verified_by":verifier.nama if verifier else None,
        "verified_at":k.verified_at.strftime("%Y-%m-%d %H:%M") if k.verified_at else None,
        "created_at":k.created_at.strftime("%Y-%m-%d %H:%M") if k.created_at else None}

@app.get("/api/compensations/me")
def my_compensations(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    synced=sync_kompensasi(db)
    if synced["created"] or synced["cancelled"]: db.commit()
    bills=db.query(Kompensasi).filter(Kompensasi.warga_id==u.id,Kompensasi.status=="belum").order_by(Kompensasi.tanggal.desc()).all()
    return {"items":[kompensasi_dict(k,u,db) for k in bills],"count":len(bills),"total":sum(k.nominal or 0 for k in bills)}

@app.get("/api/management/compensations")
def management_compensations(status:str=None,grup_id:int=None,u:Warga=Depends(require_manager),db:Session=Depends(get_db)):
    synced=sync_kompensasi(db)
    if synced["created"] or synced["cancelled"]: db.commit()
    q=db.query(Kompensasi,Warga).join(Warga,Kompensasi.warga_id==Warga.id).filter(Kompensasi.status!="dihapus")
    if u.role=="koordinator": q=q.filter(Kompensasi.grup_id==u.grup_id)
    elif grup_id is not None: q=q.filter(Kompensasi.grup_id==grup_id)
    if status and status!="all": q=q.filter(Kompensasi.status==status)
    rows=q.order_by(Kompensasi.tanggal.desc(),Warga.nama).limit(2000).all()
    return {"items":[kompensasi_dict(k,w,db) for k,w in rows],
        "summary":{"total":len(rows),"belum":sum(1 for k,_ in rows if k.status=="belum"),
                   "lunas":sum(1 for k,_ in rows if k.status=="lunas"),
                   "nominal_belum":sum(k.nominal or 0 for k,_ in rows if k.status=="belum"),
                   "nominal_lunas":sum(k.nominal or 0 for k,_ in rows if k.status=="lunas")}}

@app.post("/api/management/compensations/{cid}/verify")
def verify_compensation(cid:int,action:str=Form("paid"),catatan:str=Form(""),
                        u:Warga=Depends(require_manager),db:Session=Depends(get_db)):
    bill=db.query(Kompensasi).filter(Kompensasi.id==cid).first()
    if not bill: raise HTTPException(404,"Tagihan kompensasi tidak ditemukan.")
    if u.role=="koordinator" and bill.grup_id!=u.grup_id: raise HTTPException(403,"Bukan tagihan grup Anda.")
    if action not in ("paid","cancel"): raise HTTPException(400,"Aksi tidak valid.")
    bill.status="lunas" if action=="paid" else "dibatalkan"; bill.verified_by=u.id
    bill.verified_at=datetime.utcnow(); bill.catatan=catatan.strip()[:300]
    db.query(Notifikasi).filter(Notifikasi.tipe=="kompensasi",Notifikasi.source_id==bill.id).delete(synchronize_session=False)
    target=db.query(Warga).filter(Warga.id==bill.warga_id).first()
    if action=="paid":
        push_notif(db,"kompensasi", "✅ Kompensasi Terverifikasi",
            f"Pembayaran Rp{bill.nominal:,} untuk {bill.tanggal} telah diverifikasi oleh {u.nama}.",warga_id=bill.warga_id,source_id=bill.id)
    audit(db,u.id,"VERIFY_KOMPENSASI",f"ID:{cid} status:{bill.status} warga:{target.nama if target else bill.warga_id}")
    db.commit(); return {"message":"Pembayaran kompensasi terverifikasi." if action=="paid" else "Tagihan kompensasi dibatalkan."}

@app.delete("/api/admin/compensations/{cid}")
def delete_compensation(cid:int,alasan:str=Form("Tagihan salah"),
                        u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    bill=db.query(Kompensasi).filter(Kompensasi.id==cid,Kompensasi.status!="dihapus").first()
    if not bill: raise HTTPException(404,"Tagihan kompensasi tidak ditemukan atau sudah dihapus.")
    target=db.query(Warga).filter(Warga.id==bill.warga_id).first()
    reason=(alasan or "Tagihan salah").strip()[:220]
    bill.status="dihapus"; bill.verified_by=u.id; bill.verified_at=datetime.utcnow()
    bill.catatan=f"Dihapus admin: {reason}"[:300]
    db.query(Notifikasi).filter(Notifikasi.tipe=="kompensasi",Notifikasi.source_id==bill.id).delete(synchronize_session=False)
    audit(db,u.id,"DELETE_KOMPENSASI",
          f"ID:{cid} warga:{target.nama if target else bill.warga_id} tanggal:{bill.tanggal} alasan:{reason}")
    db.commit()
    return {"message":f"Tagihan {target.nama if target else bill.warga_id} dihapus dan tidak akan dibuat ulang."}

@app.get("/api/management/compensations/export")
def export_compensations(status:str="all",grup_id:int=None,u:Warga=Depends(require_manager),db:Session=Depends(get_db)):
    q=db.query(Kompensasi,Warga).join(Warga,Kompensasi.warga_id==Warga.id).filter(Kompensasi.status!="dihapus")
    if u.role=="koordinator": q=q.filter(Kompensasi.grup_id==u.grup_id)
    elif grup_id is not None: q=q.filter(Kompensasi.grup_id==grup_id)
    if status!="all": q=q.filter(Kompensasi.status==status)
    rows=q.order_by(Kompensasi.tanggal.desc(),Warga.nama).all(); wb=Workbook(); ws=wb.active; ws.title="laporan_kompensasi"
    headers=["ID","Tanggal","Hari","ID Warga","Nama","No. HP","Grup","Nominal","Status","Alasan","Diverifikasi Oleh","Waktu Verifikasi","Catatan","Dibuat"]
    ws.append(headers); ws.freeze_panes="A2"; ws.auto_filter.ref="A1:N1"
    for c in ws[1]: c.font=Font(bold=True,color="FFFFFF"); c.fill=PatternFill("solid",fgColor="4F46E5")
    for k,w in rows:
        d=kompensasi_dict(k,w,db); ws.append([k.id,k.tanggal,k.hari,w.akun_id,w.nama,w.no_hp,k.grup_id,k.nominal,k.status,k.alasan,d["verified_by"],d["verified_at"],k.catatan,d["created_at"]])
    widths=[8,14,12,12,26,18,9,15,13,34,24,20,32,20]
    for i,width in enumerate(widths,1): ws.column_dimensions[ws.cell(1,i).column_letter].width=width
    out=io.BytesIO(); wb.save(out); out.seek(0)
    return StreamingResponse(out,media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition":f"attachment; filename=laporan_kompensasi_{date.today()}.xlsx"})

# ── CHAT ─────────────────────────────────────────────────
def allowed_chat_group(u:Warga,db:Session,room_id=None):
    gid=int(u.grup_id if room_id is None else room_id)
    if gid==0: return 0
    if gid==u.grup_id: return gid
    accepted=db.query(ChatInvite).filter(ChatInvite.grup_id==gid,ChatInvite.ke_id==u.id,ChatInvite.status=="accepted").first()
    if not accepted: raise HTTPException(403,"Anda tidak memiliki akses ke ruang chat ini.")
    return gid

@app.get("/api/group/chat/rooms")
def chat_rooms(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    gids={u.grup_id}
    gids.update(x[0] for x in db.query(ChatInvite.grup_id).filter(ChatInvite.ke_id==u.id,ChatInvite.status=="accepted").all())
    rooms=[{"grup_id":0,"nama":"Ruang Chat Warga","utama":False,"umum":True}]
    rooms.extend({"grup_id":gid,"nama":group_nama(db,gid),"utama":gid==u.grup_id,"umum":False} for gid in sorted(gids) if gid!=0)
    return rooms

@app.get("/api/group/chat")
def get_chat(since:str=None,room_id:int=None,u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    gid=allowed_chat_group(u,db,room_id)
    q=db.query(ChatMessage).filter(ChatMessage.grup_id==gid)
    if since:
        dt=parse_dt(since)
        if dt: q=q.filter(ChatMessage.timestamp>dt)
    msgs=q.order_by(ChatMessage.timestamp.desc()).limit(80).all(); result=[]
    for m in msgs:
        w=db.query(Warga).filter(Warga.id==m.warga_id).first()
        result.append({"id":m.id,"nama":w.nama if w else "?","foto":w.foto_profil if w else None,
                       "tipe":m.tipe,"pesan":m.pesan,"waktu":m.timestamp.strftime("%H:%M"),
                       "tanggal":m.timestamp.strftime("%Y-%m-%d"),"is_mine":m.warga_id==u.id,
                       "is_deleted":bool(m.is_deleted),"reply_to_id":m.reply_to_id,"reply_preview":m.reply_preview,
                       "media":json_list(m.media_paths)})
    result.reverse()
    return {"messages":result,"grup_id":gid,"server_time":datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S.%f")}

@app.post("/api/group/chat")
def send_chat(pesan:str=Form(...),reply_to_id:int=Form(None),room_id:int=Form(None),
              u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    gid=allowed_chat_group(u,db,room_id)
    if not pesan.strip(): raise HTTPException(400,"Pesan kosong.")
    rp=None
    if reply_to_id:
        orig=db.query(ChatMessage).filter(ChatMessage.id==reply_to_id,ChatMessage.grup_id==gid).first()
        if orig and not orig.is_deleted: rp=orig.pesan[:100]
    msg=ChatMessage(grup_id=gid,warga_id=u.id,tipe="text",pesan=pesan[:500].strip(),
                    reply_to_id=reply_to_id,reply_preview=rp)
    db.add(msg)
    if gid==0:
        push_all_users(db,"chat",f"💬 {u.nama}",pesan[:100],exclude_id=u.id)
    else:
        push_notif(db,"chat",f"💬 {u.nama}",pesan[:100],grup_id=gid,exclude_id=u.id)
        guests=db.query(ChatInvite.ke_id).filter(ChatInvite.grup_id==gid,ChatInvite.status=="accepted",ChatInvite.ke_id!=u.id).distinct().all()
        for (guest_id,) in guests: push_notif(db,"chat",f"💬 {u.nama}",pesan[:100],warga_id=guest_id)
    db.commit()
    return {"message":"ok","id":msg.id}

@app.delete("/api/group/chat/{msg_id}")
def delete_msg(msg_id:int,u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    msg=db.query(ChatMessage).filter(ChatMessage.id==msg_id).first()
    if not msg: raise HTTPException(404,"Pesan tidak ditemukan.")
    allowed_chat_group(u,db,msg.grup_id)
    if msg.warga_id!=u.id and u.role not in ("admin","super_admin"):
        raise HTTPException(403,"Tidak bisa hapus pesan orang lain.")
    msg.pesan="[Pesan dihapus]"; msg.tipe="deleted"; msg.is_deleted=True; msg.media_paths=None
    db.commit()
    return {"message":"Pesan dihapus."}

@app.get("/api/group/chat/invites")
def get_invites(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    invs=db.query(ChatInvite).filter(ChatInvite.ke_id==u.id,ChatInvite.status=="pending").all(); result=[]
    for inv in invs:
        dari=db.query(Warga).filter(Warga.id==inv.dari_id).first()
        result.append({"id":inv.id,"grup_id":inv.grup_id,"dari":dari.nama if dari else "?","waktu":inv.timestamp.strftime("%Y-%m-%d %H:%M")})
    return {"invites":result}

@app.post("/api/group/chat/invite")
def chat_invite(target_hp:str=Form(...),u:Warga=Depends(require_chat_manager),db:Session=Depends(get_db)):
    target=find_warga(db,target_hp)
    if target and not target.is_active: target=None
    if not target: raise HTTPException(404,"Warga tidak ditemukan.")
    if target.grup_id==u.grup_id: raise HTTPException(400,"Warga sudah dalam grup ini.")
    ex=db.query(ChatInvite).filter(ChatInvite.grup_id==u.grup_id,ChatInvite.ke_id==target.id,
        ChatInvite.status.in_(["pending","accepted"])).first()
    if ex: raise HTTPException(400,"Warga sudah diundang atau telah bergabung.")
    db.add(ChatInvite(grup_id=u.grup_id,dari_id=u.id,ke_id=target.id))
    push_notif(db,"invite",f"📨 Undangan Chat",f"{u.nama} mengundang ke chat Grup {u.grup_id}",warga_id=target.id)
    db.commit(); return {"message":f"Undangan dikirim ke {target.nama}!"}

@app.put("/api/group/chat/invite/{inv_id}")
def respond_invite(inv_id:int,accept:bool=Form(...),u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    inv=db.query(ChatInvite).filter(ChatInvite.id==inv_id,ChatInvite.ke_id==u.id).first()
    if not inv: raise HTTPException(404,"Undangan tidak ditemukan.")
    inv.status="accepted" if accept else "rejected"
    if accept: db.add(ChatMessage(grup_id=inv.grup_id,warga_id=u.id,tipe="system",pesan=f"{u.nama} bergabung ke chat grup."))
    db.commit(); return {"message":"Bergabung!" if accept else "Ditolak."}

# ── NOTIFIKASI ────────────────────────────────────────────
@app.get("/api/push/config")
def push_config(u:Warga=Depends(current_user)):
    return {"enabled":bool(VAPID_PUBLIC_KEY and Path(VAPID_PRIVATE_KEY_PATH).exists()),"public_key":VAPID_PUBLIC_KEY}

@app.post("/api/push/subscribe")
def push_subscribe(subscription:str=Form(...),request:Request=None,
                   u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    try: data=json.loads(subscription)
    except Exception: raise HTTPException(400,"Data langganan push tidak valid.")
    endpoint=str(data.get("endpoint") or "").strip(); keys=data.get("keys") or {}
    p256dh=str(keys.get("p256dh") or "").strip(); auth=str(keys.get("auth") or "").strip()
    if not endpoint.startswith("https://") or not p256dh or not auth or len(endpoint)>2500:
        raise HTTPException(400,"Langganan push tidak lengkap.")
    sub=db.query(PushSubscription).filter(PushSubscription.endpoint==endpoint).first()
    if not sub:
        sub=PushSubscription(endpoint=endpoint,warga_id=u.id,p256dh=p256dh,auth=auth); db.add(sub)
    sub.warga_id=u.id; sub.p256dh=p256dh; sub.auth=auth; sub.last_seen=datetime.utcnow()
    sub.user_agent=(request.headers.get("user-agent","") if request else "")[:300]
    db.flush()
    older=db.query(PushSubscription).filter(PushSubscription.warga_id==u.id,PushSubscription.id!=sub.id).order_by(PushSubscription.last_seen.desc()).all()
    for stale in older[4:]: db.delete(stale)
    audit(db,u.id,"PUSH_SUBSCRIBE","Web Push diaktifkan"); db.commit()
    return {"message":"Notifikasi Web Push aktif."}

@app.post("/api/push/unsubscribe")
def push_unsubscribe(endpoint:str=Form(...),u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    removed=db.query(PushSubscription).filter(PushSubscription.warga_id==u.id,PushSubscription.endpoint==endpoint).delete()
    audit(db,u.id,"PUSH_UNSUBSCRIBE",f"Dihapus:{removed}"); db.commit()
    return {"message":"Notifikasi Web Push dinonaktifkan."}

@app.post("/api/push/test")
def push_test(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    count=send_web_push(db,"chat","🔔 Tes Web Push",f"Notifikasi untuk {u.nama} berhasil terhubung.",warga_id=u.id)
    db.commit()
    if not count: raise HTTPException(400,"Belum ada perangkat push aktif atau layanan push tidak terjangkau.")
    return {"message":"Notifikasi tes dikirim."}

@app.get("/api/notifications")
def get_notifs(since:str=None,u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    visible=or_(Notifikasi.warga_id==u.id,
        and_(Notifikasi.grup_id==u.grup_id,Notifikasi.warga_id==None),
        and_(Notifikasi.grup_id==None,Notifikasi.warga_id==None))
    q=db.query(Notifikasi).filter(visible)
    if since:
        dt=parse_dt(since)
        if dt: q=q.filter(Notifikasi.timestamp>dt)
    notifs=q.order_by(Notifikasi.timestamp.desc()).limit(30).all()
    unread=db.query(Notifikasi).filter(or_(Notifikasi.warga_id==u.id,Notifikasi.grup_id==u.grup_id),Notifikasi.dibaca==False).count()
    active_ids=[row[0] for row in db.query(Notifikasi.id).filter(visible).order_by(Notifikasi.id.desc()).limit(300).all()]
    return {"notifications":[{"id":n.id,"tipe":n.tipe,"judul":n.judul,"pesan":n.pesan,
                               "dibaca":n.dibaca,"timestamp":n.timestamp.strftime("%Y-%m-%d %H:%M:%S.%f")} for n in notifs],
            "unread":unread,"active_ids":active_ids,"server_time":datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S.%f")}

@app.post("/api/notifications/read")
def mark_read(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    db.query(Notifikasi).filter(or_(Notifikasi.warga_id==u.id,Notifikasi.grup_id==u.grup_id)).update({"dibaca":True})
    db.commit(); return {"message":"ok"}

@app.post("/api/notifications/read/chat")
def mark_chat_read(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    db.query(Notifikasi).filter(
        or_(Notifikasi.warga_id==u.id,Notifikasi.grup_id==u.grup_id),
        Notifikasi.tipe.in_(["chat","invite"])).update({"dibaca":True})
    db.commit()
    unread=db.query(Notifikasi).filter(or_(Notifikasi.warga_id==u.id,Notifikasi.grup_id==u.grup_id),Notifikasi.dibaca==False).count()
    return {"message":"ok","unread":unread}

@app.delete("/api/notifications/{nid}")
def delete_notif(nid:int,u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    db.query(Notifikasi).filter(Notifikasi.id==nid,
        or_(Notifikasi.warga_id==u.id,Notifikasi.grup_id==u.grup_id)).delete()
    db.commit(); return {"message":"ok"}

@app.delete("/api/notifications")
def delete_all_notifs(u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    db.query(Notifikasi).filter(or_(Notifikasi.warga_id==u.id,Notifikasi.grup_id==u.grup_id)).delete()
    db.commit(); return {"message":"ok"}

# ── SOS ──────────────────────────────────────────────────
@app.post("/api/emergency/sos")
def sos(lat:float=Form(...),lon:float=Form(...),keterangan:str=Form("Butuh bantuan!"),
        u:Warga=Depends(current_user),db:Session=Depends(get_db)):
    alert=Emergency(warga_id=u.id,lat=lat,lon=lon,ket=keterangan[:200]); db.add(alert); db.flush()
    push_all_users(db,"sos",f"🆘 SOS! {u.nama}",f"GPS:{lat:.5f},{lon:.5f} — {keterangan}",source_id=alert.id)
    audit(db,u.id,"SOS_ALERT",f"GPS:{lat:.5f},{lon:.5f}"); db.commit()
    logger.warning(f"SOS! {u.nama}({u.no_hp}) GPS:{lat},{lon}")
    return {"message":"Sinyal darurat dikirim! Tim ronda diberitahu."}

# ── ADMIN: WARGA ──────────────────────────────────────────
@app.get("/api/admin/warga")
def admin_list_warga(grup:int=None,u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    q=db.query(Warga)
    if grup is not None: q=q.filter(Warga.grup_id==grup)
    return [warga_dict(w) for w in q.order_by(Warga.grup_id,Warga.nama).all()]

@app.get("/api/admin/warga/simple")
def warga_simple(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    ws=db.query(Warga).filter(Warga.is_active==True).order_by(Warga.grup_id,Warga.nama).all()
    return [{"id":w.id,"akun_id":w.akun_id,"nama":w.nama,"no_hp":w.no_hp,"grup_id":w.grup_id,"role":w.role,"foto":w.foto_profil} for w in ws]

@app.post("/api/admin/warga")
def admin_add_warga(nama:str=Form(...),no_hp:str=Form(...),tanggal_lahir:str=Form(...),grup_id:int=Form(...),
                    role:str=Form("warga"),catatan:str=Form(""),akun_id:str=Form(""),
                    u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    if db.query(Warga).filter(Warga.no_hp==no_hp.strip()).first(): raise HTTPException(400,f"No. HP {no_hp} sudah ada.")
    if role not in ("warga","koordinator","admin","super_admin"): raise HTTPException(400,"Role tidak valid.")
    if role=="super_admin" and u.role!="super_admin": raise HTTPException(403,"Hanya Super Admin.")
    aid=validate_akun_id(akun_id,role) if akun_id else next_akun_id(db,role)
    if db.query(Warga).filter(func.upper(Warga.akun_id)==aid).first(): raise HTTPException(400,f"ID warga {aid} sudah digunakan.")
    nw=Warga(nama=nama.strip(),akun_id=aid,no_hp=no_hp.strip(),tanggal_lahir=tanggal_lahir.strip(),grup_id=grup_id,role=role,catatan=catatan)
    db.add(nw); audit(db,u.id,"ADD_WARGA",f"{nama}({no_hp})"); db.commit(); db.refresh(nw)
    return {"message":f"{nama} berhasil didaftarkan dengan ID {aid}!","id":nw.id,"akun_id":aid}

@app.put("/api/admin/warga/{wid}")
def admin_edit_warga(wid:int,nama:str=Form(None),no_hp:str=Form(None),tanggal_lahir:str=Form(None),
                     grup_id:int=Form(None),role:str=Form(None),catatan:str=Form(None),is_active:bool=Form(None),akun_id:str=Form(None),
                     u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    w=db.query(Warga).filter(Warga.id==wid).first()
    if not w: raise HTTPException(404,"Warga tidak ditemukan.")
    if w.role=="super_admin" and u.role!="super_admin": raise HTTPException(403,"Tidak bisa edit Super Admin.")
    if nama: w.nama=nama.strip()
    old_role=w.role; new_role=role if role in ("warga","koordinator","admin") else old_role
    if akun_id is not None and akun_id.strip()!=w.akun_id:
        aid=validate_akun_id(akun_id,new_role)
        if db.query(Warga).filter(func.upper(Warga.akun_id)==aid,Warga.id!=wid).first():
            raise HTTPException(400,f"ID warga {aid} sudah digunakan warga lain.")
        w.akun_id=aid
    elif new_role!=old_role and w.akun_id:
        w.akun_id=next_akun_id(db,new_role,w.id)
    if no_hp and no_hp.strip()!=w.no_hp:
        ex=db.query(Warga).filter(Warga.no_hp==no_hp.strip(),Warga.id!=wid).first()
        if ex: raise HTTPException(400,f"No. HP {no_hp} sudah digunakan warga lain.")
        w.no_hp=no_hp.strip()
    if tanggal_lahir: w.tanggal_lahir=tanggal_lahir.strip()
    if grup_id is not None: w.grup_id=grup_id
    w.role=new_role
    if catatan is not None: w.catatan=catatan
    if is_active is not None: w.is_active=is_active
    audit(db,u.id,"EDIT_WARGA",f"ID:{wid}"); db.commit()
    return {"message":f"Data {w.nama} diperbarui."}

# ── ADMIN: ABSENSI MANUAL ─────────────────────────────────
@app.get("/api/admin/attendance")
def admin_attendance(tanggal:str=None,u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    tgl=tanggal or date.today().isoformat()
    rows=db.query(Attendance,Warga).join(Warga,Attendance.warga_id==Warga.id).filter(
        Attendance.tanggal==tgl).order_by(Warga.grup_id,Warga.nama).all()
    return [{"id":a.id,"warga_id":w.id,"akun_id":w.akun_id,"nama":w.nama,"grup_id":w.grup_id,
             "status":a.status or "hadir","keterangan":a.keterangan or "",
             "check_in":a.check_in.strftime("%H:%M") if a.check_in else None,
             "check_out":a.check_out.strftime("%H:%M") if a.check_out else None,
             "manual":bool(a.manual_by)} for a,w in rows]

@app.post("/api/admin/attendance/manual")
def admin_manual_attendance(warga_id:int=Form(...),tanggal:str=Form(...),status:str=Form(...),
                            keterangan:str=Form(""),jam_masuk:str=Form(""),jam_keluar:str=Form(""),
                            u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    allowed={"hadir","izin","sakit","alpa","lainnya"}
    status=status.lower().strip()
    if status not in allowed: raise HTTPException(400,"Status absensi tidak valid.")
    try: base=datetime.strptime(tanggal,"%Y-%m-%d")
    except ValueError: raise HTTPException(400,"Format tanggal tidak valid.")
    w=db.query(Warga).filter(Warga.id==warga_id,Warga.is_active==True).first()
    if not w: raise HTTPException(404,"Warga tidak ditemukan.")
    a=db.query(Attendance).filter(Attendance.warga_id==warga_id,Attendance.tanggal==tanggal).order_by(Attendance.id.desc()).first()
    if not a:
        a=Attendance(warga_id=warga_id,tanggal=tanggal); db.add(a)
    def at_time(value):
        if not value: return None
        try:
            hh,mm=map(int,value.split(":")); return base.replace(hour=hh,minute=mm)
        except: raise HTTPException(400,"Format jam tidak valid.")
    a.status=status; a.keterangan=keterangan.strip()[:300]; a.manual_by=u.id
    a.check_in=at_time(jam_masuk) if status=="hadir" else None
    a.check_out=at_time(jam_keluar) if status=="hadir" else None
    a.cp_in="MANUAL" if a.check_in else None; a.cp_out="MANUAL" if a.check_out else None
    a.durasi_menit=max(0,int((a.check_out-a.check_in).total_seconds()/60)) if a.check_in and a.check_out else None
    db.flush(); sync_kompensasi(db)
    push_notif(db,"attendance",f"📝 Absensi {w.nama}",f"Status {status.title()} untuk {tanggal}",grup_id=w.grup_id)
    audit(db,u.id,"ABSEN_MANUAL",f"{w.nama} {tanggal}: {status} - {keterangan}"); db.commit()
    return {"message":f"Absensi {w.nama} disimpan sebagai {status.title()}."}

# ── ADMIN: GRUP ───────────────────────────────────────────
@app.get("/api/admin/groups")
def admin_groups(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    grups=db.query(Warga.grup_id).filter(Warga.is_active==True,Warga.grup_id>0).distinct().all(); result=[]
    for (gid,) in grups:
        info=db.query(GroupInfo).filter(GroupInfo.grup_id==gid).first()
        count=db.query(Warga).filter(Warga.grup_id==gid,Warga.is_active==True).count()
        js=db.query(JadwalRonda).filter(JadwalRonda.grup_id==gid,JadwalRonda.is_active==True).count()
        result.append({"grup_id":gid,"nama":info.nama if info else f"Grup {gid}",
                       "deskripsi":info.deskripsi if info else "","jumlah_anggota":count,"jumlah_jadwal":js})
    result.sort(key=lambda x:x["grup_id"])
    return result

@app.put("/api/admin/group/{gid}")
def update_group(gid:int,nama:str=Form(...),deskripsi:str=Form(""),
                 u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    info=db.query(GroupInfo).filter(GroupInfo.grup_id==gid).first()
    if not info: db.add(GroupInfo(grup_id=gid,nama=nama.strip(),deskripsi=deskripsi))
    else: info.nama=nama.strip(); info.deskripsi=deskripsi; info.updated_at=datetime.utcnow()
    audit(db,u.id,"UPDATE_GROUP",f"Grup{gid} nama:{nama}"); db.commit()
    return {"message":f"Grup {gid} diperbarui."}

# ── ADMIN: CHECKPOINT ─────────────────────────────────────
@app.get("/api/admin/checkpoints")
def admin_list_cp(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    return [{"id":c.id,"nama":c.nama,"token":c.token,"tipe":c.tipe,"urutan":c.urutan or 0,
             "lokasi":c.lokasi,"lat":c.lat,"lon":c.lon,"radius_meter":max(25,min(1000,c.radius_meter or 30)),
             "is_active":c.is_active}
            for c in db.query(Checkpoint).order_by(Checkpoint.tipe,Checkpoint.urutan,Checkpoint.id).all()]

@app.post("/api/admin/checkpoint")
def admin_add_cp(nama:str=Form(...),token:str=Form(...),tipe:str=Form("patrol"),lokasi:str=Form(""),
                 lat:float=Form(None),lon:float=Form(None),urutan:int=Form(None),radius_meter:int=Form(30),
                 u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    tkn=re.sub(r'[^A-Z0-9\-]','',token.upper().strip())
    if not tkn: raise HTTPException(400,"Token tidak valid.")
    if db.query(Checkpoint).filter(Checkpoint.token==tkn).first(): raise HTTPException(400,f"Token '{tkn}' sudah ada.")
    if tipe=="patrol":
        if urutan is None: urutan=(db.query(func.max(Checkpoint.urutan)).filter(Checkpoint.tipe=="patrol").scalar() or 0)+1
        else:
            urutan=max(1,urutan)
            for item in db.query(Checkpoint).filter(Checkpoint.tipe=="patrol",Checkpoint.urutan>=urutan).order_by(Checkpoint.urutan.desc()).all():
                item.urutan=(item.urutan or 0)+1
    radius_meter=max(25,min(1000,radius_meter or 30))
    db.add(Checkpoint(nama=nama.strip(),token=tkn,tipe=tipe,lokasi=lokasi,lat=lat,lon=lon,
        urutan=urutan or 0,radius_meter=radius_meter))
    audit(db,u.id,"ADD_CHECKPOINT",f"{nama}({tkn})"); db.commit()
    return {"message":f"Checkpoint '{nama}' ditambahkan!"}

@app.put("/api/admin/checkpoint/{cid}")
def admin_edit_cp(cid:int,nama:str=Form(None),lokasi:str=Form(None),lat:float=Form(None),lon:float=Form(None),
                  urutan:int=Form(None),radius_meter:int=Form(None),is_active:bool=Form(None),
                  u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    c=db.query(Checkpoint).filter(Checkpoint.id==cid).first()
    if not c: raise HTTPException(404,"Tidak ditemukan.")
    if nama: c.nama=nama.strip()
    if lokasi is not None: c.lokasi=lokasi
    if lat is not None: c.lat=lat
    if lon is not None: c.lon=lon
    if urutan is not None: c.urutan=max(0,urutan)
    if radius_meter is not None: c.radius_meter=max(25,min(1000,radius_meter))
    if is_active is not None: c.is_active=is_active
    audit(db,u.id,"EDIT_CHECKPOINT",f"ID:{cid}"); db.commit()
    return {"message":"Checkpoint diperbarui."}

@app.post("/api/admin/checkpoint/{cid}/move")
def admin_move_cp(cid:int,direction:str=Form(...),u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    if direction not in ("up","down"): raise HTTPException(400,"Arah tidak valid.")
    ordered=db.query(Checkpoint).filter(Checkpoint.tipe=="patrol").order_by(Checkpoint.urutan,Checkpoint.id).all()
    for number,item in enumerate(ordered,1): item.urutan=number
    current=next((i for i,item in enumerate(ordered) if item.id==cid),None)
    if current is None: raise HTTPException(404,"Checkpoint patroli tidak ditemukan.")
    target=current-1 if direction=="up" else current+1
    if target<0 or target>=len(ordered): return {"message":"Checkpoint sudah berada di ujung rute."}
    ordered[current].urutan,ordered[target].urutan=ordered[target].urutan,ordered[current].urutan
    audit(db,u.id,"MOVE_CHECKPOINT",f"ID:{cid} arah:{direction}"); db.commit()
    return {"message":"Urutan rute diperbarui."}

# ── ADMIN: PENGATURAN ─────────────────────────────────────
@app.get("/api/admin/settings")
def admin_get_settings(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    return [{"key":s.key,"value":s.value,"label":s.label,"updated_at":s.updated_at.strftime("%Y-%m-%d %H:%M") if s.updated_at else None}
            for s in db.query(Setting).all()]

@app.post("/api/admin/settings")
def admin_save_setting(key:str=Form(...),value:str=Form(...),u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    s=db.query(Setting).filter(Setting.key==key).first()
    if not s: raise HTTPException(404,"Setting tidak ada.")
    value=value.strip()
    if key=="retensi_foto_hari" and value not in ("3","7","14","manual"):
        raise HTTPException(400,"Retensi foto harus 3, 7, 14 hari, atau manual.")
    if key=="radius_checkpoint_meter":
        try: value=str(max(25,min(1000,int(value))))
        except Exception: raise HTTPException(400,"Radius default harus berupa angka 25–1000 meter.")
    s.value=value; s.updated_at=datetime.utcnow()
    audit(db,u.id,"UPDATE_SETTING",f"{key}={value}"); db.commit()
    return {"message":"Pengaturan diperbarui."}

# ── ADMIN: STATISTIK & LAPORAN ────────────────────────────
@app.get("/api/admin/stats")
def admin_stats(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    synced=sync_kompensasi(db)
    if synced["created"] or synced["cancelled"]: db.commit()
    today=date.today().isoformat(); month=date.today().strftime("%Y-%m")
    return {"total_warga":db.query(Warga).filter(Warga.is_active==True).count(),
            "total_grup":db.query(Warga.grup_id).filter(Warga.is_active==True).distinct().count(),
            "absen_hari_ini":db.query(Attendance).filter(Attendance.tanggal==today).count(),
            "absen_bulan_ini":db.query(Attendance).filter(Attendance.tanggal.like(f"{month}%")).count(),
            "patroli_hari_ini":db.query(PatrolVisit).filter(func.date(PatrolVisit.timestamp)==today).count(),
            "patroli_bulan_ini":db.query(PatrolVisit).filter(PatrolVisit.timestamp>=datetime.strptime(month,"%Y-%m")).count(),
            "emergency_aktif":db.query(Emergency).filter(Emergency.resolved==False).count(),
            "kompensasi_belum":db.query(Kompensasi).filter(Kompensasi.status=="belum").count(),
            "total_checkpoint":db.query(Checkpoint).filter(Checkpoint.is_active==True).count()}

def excel_report_response(sheet_name,headers,rows,filename):
    """Buat Excel asli: satu field satu kolom, bukan CSV berkoma."""
    wb=Workbook(); ws=wb.active; ws.title=sheet_name[:31]; ws.freeze_panes="A2"
    ws.append(headers)
    for cell in ws[1]:
        cell.font=Font(bold=True,color="FFFFFF"); cell.fill=PatternFill("solid",fgColor="4F46E5")
        cell.alignment=Alignment(horizontal="center",vertical="center")
    for row in rows:
        safe=[]
        for value in row:
            if isinstance(value,str) and value[:1] in ("=","+","-","@"): value="'"+value
            safe.append(value)
        ws.append(safe)
    ws.auto_filter.ref=ws.dimensions
    for idx,header in enumerate(headers,1):
        longest=max((len(str(ws.cell(row,idx).value or "")) for row in range(1,min(ws.max_row,200)+1)),default=len(header))
        ws.column_dimensions[ws.cell(1,idx).column_letter].width=max(12,min(45,longest+2))
    out=io.BytesIO(); wb.save(out); out.seek(0)
    return StreamingResponse(out,media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition":f"attachment; filename={filename}"})

@app.get("/api/admin/reports/attendance")
def export_absensi(tgl_mulai:str=None,tgl_selesai:str=None,u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    q=db.query(Attendance,Warga).join(Warga,Attendance.warga_id==Warga.id)
    if tgl_mulai: q=q.filter(Attendance.tanggal>=tgl_mulai)
    if tgl_selesai: q=q.filter(Attendance.tanggal<=tgl_selesai)
    headers=["Tanggal","ID Warga","Nama","No HP","Grup","Role","Status","Keterangan","Check-IN","Pos IN","Check-OUT","Pos OUT","Durasi (menit)"]
    rows=[]
    for a,wr in q.order_by(Attendance.tanggal.desc()).all():
        rows.append([a.tanggal,wr.akun_id,wr.nama,wr.no_hp,wr.grup_id,wr.role,a.status or "hadir",a.keterangan or "",
                    a.check_in.strftime("%H:%M") if a.check_in else "-",a.cp_in or "-",
                    a.check_out.strftime("%H:%M") if a.check_out else "-",a.cp_out or "-",a.durasi_menit if a.durasi_menit is not None else "-"])
    return excel_report_response("absensi",headers,rows,f"absensi_{date.today()}.xlsx")

@app.get("/api/admin/reports/patrol")
def export_patroli(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    rows=db.query(PatrolVisit,Warga).join(Warga,PatrolVisit.warga_id==Warga.id).order_by(PatrolVisit.timestamp.desc()).limit(2000).all()
    headers=["Waktu","ID Warga","Nama","No HP","Grup","Checkpoint","Keterangan","Latitude","Longitude"]
    values=[[p.timestamp.strftime("%Y-%m-%d %H:%M"),wr.akun_id,wr.nama,wr.no_hp,wr.grup_id,
             p.cp_nama or p.cp_token,p.keterangan,p.lat,p.lon] for p,wr in rows]
    return excel_report_response("patroli",headers,values,f"patroli_{date.today()}.xlsx")

# ── ADMIN: IMPOR / EKSPOR DATA ────────────────────────────
@app.get("/api/admin/data/datasets")
def admin_data_datasets(u:Warga=Depends(require_admin)):
    return [{"key":key,"label":DATASET_CONFIG[key]["label"]} for key in DATASET_ORDER]

@app.get("/api/admin/data/export")
def admin_export_data(format:str="json",datasets:str="all",u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    names=selected_datasets(datasets); fmt=format.lower().strip()
    if fmt not in ("json","xlsx"): raise HTTPException(400,"Format harus json atau xlsx.")
    payload={}
    for name in names:
        cfg=DATASET_CONFIG[name]; rows=db.query(cfg["model"]).all()
        payload[name]=[{field:export_cell(getattr(row,field,None)) for field in cfg["fields"]} for row in rows]
    stamp=datetime.now().strftime("%Y%m%d_%H%M%S")
    if fmt=="json":
        document={"app":"Siskamling Digital","version":VERSION,"exported_at":datetime.utcnow().isoformat(),"datasets":payload}
        raw=json.dumps(document,ensure_ascii=False,indent=2,default=str).encode("utf-8")
        return StreamingResponse(io.BytesIO(raw),media_type="application/json",
            headers={"Content-Disposition":f"attachment; filename=ronda_data_{stamp}.json"})
    wb=Workbook(); wb.remove(wb.active)
    for name in names:
        cfg=DATASET_CONFIG[name]; ws=wb.create_sheet(name[:31]); ws.freeze_panes="A2"; ws.auto_filter.ref="A1:A1"
        ws.append(cfg["fields"])
        for cell in ws[1]:
            cell.font=Font(bold=True,color="FFFFFF"); cell.fill=PatternFill("solid",fgColor="4F46E5"); cell.alignment=Alignment(horizontal="center")
        for row in payload[name]:
            values=[]
            for field in cfg["fields"]:
                val=row.get(field)
                if isinstance(val,str) and val[:1] in ("=","+","-","@"): val="'"+val
                values.append(val)
            ws.append(values)
        ws.auto_filter.ref=ws.dimensions
        for idx,field in enumerate(cfg["fields"],1):
            width=max(len(field)+2,min(40,max((len(str(ws.cell(r,idx).value or "")) for r in range(2,min(ws.max_row,100)+1)),default=8)+2))
            ws.column_dimensions[ws.cell(1,idx).column_letter].width=width
    out=io.BytesIO(); wb.save(out); out.seek(0)
    return StreamingResponse(out,media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition":f"attachment; filename=ronda_data_{stamp}.xlsx"})

@app.get("/api/admin/data/template/warga")
def admin_warga_template(u:Warga=Depends(require_admin)):
    wb=Workbook(); ws=wb.active; ws.title="warga"
    headers=["akun_id","nama","no_hp","tanggal_lahir","grup_id","role","catatan","is_active"]
    ws.append(headers); ws.freeze_panes="A2"; ws.auto_filter.ref="A1:H1"
    for c in ws[1]:
        c.font=Font(bold=True,color="FFFFFF"); c.fill=PatternFill("solid",fgColor="4F46E5"); c.alignment=Alignment(horizontal="center")
    widths=[16,28,22,20,13,18,32,14]
    for i,width in enumerate(widths,1): ws.column_dimensions[ws.cell(1,i).column_letter].width=width
    for row in range(2,1002):
        ws.cell(row,1).number_format="@"; ws.cell(row,3).number_format="@"; ws.cell(row,4).number_format="@"
    info=wb.create_sheet("PETUNJUK")
    instructions=[
        ["TEMPLATE IMPOR DATA WARGA"],
        ["Isi data mulai baris 2 pada sheet 'warga'. Jangan mengubah nama kolom."],
        ["akun_id","Opsional. Format WG00001/KR00001/AD00001/SA00001 sesuai role; kosong dibuat otomatis saat aktivasi."],
        ["nama","Wajib."],["no_hp","Wajib dan unik. Ketik sebagai teks agar angka 0 di depan tidak hilang."],
        ["tanggal_lahir","Wajib. Gunakan DD-MM-YYYY atau tanggal Excel."],
        ["grup_id","Kosong berarti Grup 1."],["role","warga / koordinator / admin. Default warga."],
        ["catatan","Opsional."],["is_active","ya/true/1 untuk aktif; tidak/false/0 untuk nonaktif."],
        ["Catatan","Data dengan akun_id atau no_hp yang sudah ada akan diperbarui saat mode Gabungkan dipakai."],
    ]
    for row in instructions: info.append(row)
    info.column_dimensions["A"].width=24; info.column_dimensions["B"].width=85; info["A1"].font=Font(bold=True,size=14)
    out=io.BytesIO(); wb.save(out); out.seek(0)
    return StreamingResponse(out,media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition":"attachment; filename=template_import_warga.xlsx"})

@app.post("/api/admin/data/import")
async def admin_import_data(file:UploadFile=File(...),datasets:str=Form("all"),mode:str=Form("merge"),
                            u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    if mode not in ("merge","new"): raise HTTPException(400,"Mode impor tidak valid.")
    content=await file.read()
    if not content: raise HTTPException(400,"File kosong.")
    if len(content)>15*1024*1024: raise HTTPException(400,"File impor maksimal 15 MB.")
    ext=(file.filename or "").rsplit(".",1)[-1].lower()
    chosen=selected_datasets(datasets); rows_by_name={}
    try:
        if ext=="json":
            parsed=json.loads(content.decode("utf-8-sig")); source=parsed.get("datasets",parsed) if isinstance(parsed,dict) else {}
            if not isinstance(source,dict): raise ValueError("Struktur JSON harus berisi objek datasets")
            for name in chosen:
                if name in source:
                    if not isinstance(source[name],list): raise ValueError(f"Dataset {name} harus berupa daftar")
                    rows_by_name[name]=source[name]
        elif ext=="xlsx":
            wb=load_workbook(io.BytesIO(content),data_only=True,read_only=True)
            sheet_map={normalize_header(ws.title):ws for ws in wb.worksheets if normalize_header(ws.title)!="petunjuk"}
            for name in chosen:
                ws=sheet_map.get(name) or sheet_map.get(normalize_header(DATASET_CONFIG[name]["label"]))
                if not ws and name=="warga" and len(chosen)==1:
                    ws=next((s for s in wb.worksheets if normalize_header(s.title)!="petunjuk"),None)
                if not ws: continue
                parsed_rows=excel_rows_by_field(ws)
                if parsed_rows: rows_by_name[name]=parsed_rows
        else: raise HTTPException(400,"Gunakan file .json atau .xlsx.")
    except HTTPException: raise
    except Exception as exc: raise HTTPException(400,f"File tidak dapat dibaca: {exc}")
    if not rows_by_name: raise HTTPException(400,"Tidak ada dataset yang cocok dengan pilihan atau nama sheet.")
    total=sum(len(rows) for rows in rows_by_name.values())
    if total>5000: raise HTTPException(400,"Maksimal 5.000 baris per impor.")
    summary={}; errors=[]
    for name in chosen:
        rows=rows_by_name.get(name,[]); counts={"created":0,"updated":0,"skipped":0,"failed":0}
        for number,row in enumerate(rows,2):
            try:
                with db.begin_nested():
                    state=import_dataset_row(db,name,row,u,mode); counts[state]+=1
            except Exception as exc:
                counts["failed"]+=1
                detail=exc.detail if isinstance(exc,HTTPException) else str(exc)
                if len(errors)<30: errors.append({"dataset":name,"baris":number,"error":detail})
        summary[name]=counts
    audit(db,u.id,"IMPORT_DATA",f"File:{file.filename} dataset:{','.join(rows_by_name)} total:{total}")
    db.commit()
    return {"message":"Impor selesai.","total_rows":total,"summary":summary,"errors":errors,
            "error_note":"Hanya 30 kesalahan pertama ditampilkan." if sum(v["failed"] for v in summary.values())>30 else None}

@app.get("/api/admin/emergency")
def admin_emergency(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    rows=db.query(Emergency,Warga).join(Warga,Emergency.warga_id==Warga.id).order_by(Emergency.ts.desc()).limit(50).all()
    return [{"id":e.id,"nama":wr.nama,"no_hp":wr.no_hp,"lat":e.lat,"lon":e.lon,"keterangan":e.ket,"waktu":e.ts.strftime("%Y-%m-%d %H:%M"),"resolved":e.resolved} for e,wr in rows]

@app.post("/api/admin/emergency/{aid}/resolve")
def resolve_sos(aid:int,u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    e=db.query(Emergency).filter(Emergency.id==aid).first()
    if not e: raise HTTPException(404,"Alert tidak ditemukan.")
    e.resolved=True; e.resolved_by=u.id; audit(db,u.id,"RESOLVE_SOS",f"AlertID:{aid}"); db.commit()
    return {"message":"Alert SOS selesai ditangani."}

@app.delete("/api/admin/emergency/{aid}")
def delete_sos_admin(aid:int,u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    e=db.query(Emergency).filter(Emergency.id==aid).first()
    if not e: raise HTTPException(404,"Alert SOS tidak ditemukan.")
    warga=db.query(Warga).filter(Warga.id==e.warga_id).first()
    # source_id menangani SOS baru; filter waktu+judul membersihkan notifikasi SOS versi lama.
    q=db.query(Notifikasi).filter(Notifikasi.tipe=="sos").filter(or_(
        Notifikasi.source_id==aid,
        and_(Notifikasi.source_id==None,
             Notifikasi.timestamp>=e.ts-timedelta(seconds=90),
             Notifikasi.timestamp<=e.ts+timedelta(seconds=90),
             Notifikasi.judul.like(f"%{warga.nama}%") if warga else Notifikasi.id<0)))
    removed=q.delete(synchronize_session=False); close_web_push_tag(db,f"sos-{aid}")
    db.delete(e); audit(db,u.id,"DELETE_SOS",f"AlertID:{aid} notif:{removed}"); db.commit()
    return {"message":"Alert SOS dan notifikasi semua warga telah dihapus.","notifications_removed":removed}

@app.get("/api/admin/audit")
def admin_audit(limit:int=100,u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    rows=db.query(AuditLog,Warga).outerjoin(Warga,AuditLog.warga_id==Warga.id).order_by(AuditLog.ts.desc()).limit(min(limit,300)).all()
    return [{"waktu":l.ts.strftime("%Y-%m-%d %H:%M:%S"),"nama":wr.nama if wr else "Sistem","action":l.action,"detail":l.detail,"ip":l.ip} for l,wr in rows]

# ── ADMIN: JADWAL ─────────────────────────────────────────
@app.get("/api/admin/schedules")
def admin_schedules(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    HARI=["Senin","Selasa","Rabu","Kamis","Jumat","Sabtu","Minggu"]
    grups=db.query(Warga.grup_id).filter(Warga.is_active==True,Warga.grup_id>0).distinct().all(); result={}
    for (gid,) in grups:
        js=db.query(JadwalRonda).filter(JadwalRonda.grup_id==gid,JadwalRonda.is_active==True).order_by(JadwalRonda.hari).all()
        result[str(gid)]=[{"id":j.id,"hari":j.hari,"hari_nama":HARI[j.hari] if j.hari is not None else "Khusus","tanggal":j.tanggal,"catatan":j.catatan} for j in js]
    return result

@app.post("/api/admin/schedule")
def add_schedule(grup_id:int=Form(...),hari:int=Form(None),tanggal:str=Form(None),catatan:str=Form(""),
                 u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    if hari is None and not tanggal: raise HTTPException(400,"Tentukan hari atau tanggal khusus.")
    if hari is not None and hari not in range(7): raise HTTPException(400,"Hari tidak valid.")
    dup=db.query(JadwalRonda).filter(JadwalRonda.grup_id==grup_id,JadwalRonda.hari==hari,
        JadwalRonda.tanggal==(tanggal or None),JadwalRonda.is_active==True).first()
    if dup: raise HTTPException(400,"Jadwal yang sama sudah tersedia.")
    db.add(JadwalRonda(grup_id=grup_id,hari=hari,tanggal=tanggal or None,catatan=catatan))
    audit(db,u.id,"ADD_JADWAL",f"Grup{grup_id} hari:{hari}"); db.commit()
    return {"message":f"Jadwal Grup {grup_id} ditambahkan."}

@app.put("/api/admin/schedule/{jid}")
def edit_schedule(jid:int,grup_id:int=Form(...),hari:int=Form(None),tanggal:str=Form(None),
                  catatan:str=Form(""),u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    j=db.query(JadwalRonda).filter(JadwalRonda.id==jid,JadwalRonda.is_active==True).first()
    if not j: raise HTTPException(404,"Jadwal tidak ditemukan.")
    if hari is None and not tanggal: raise HTTPException(400,"Tentukan hari atau tanggal khusus.")
    if hari is not None and hari not in range(7): raise HTTPException(400,"Hari tidak valid.")
    dup=db.query(JadwalRonda).filter(JadwalRonda.id!=jid,JadwalRonda.grup_id==grup_id,
        JadwalRonda.hari==hari,JadwalRonda.tanggal==(tanggal or None),JadwalRonda.is_active==True).first()
    if dup: raise HTTPException(400,"Jadwal yang sama sudah tersedia.")
    j.grup_id=grup_id; j.hari=hari; j.tanggal=tanggal or None; j.catatan=catatan.strip()[:200]
    audit(db,u.id,"EDIT_JADWAL",f"ID:{jid} Grup:{grup_id}"); db.commit()
    return {"message":"Jadwal berhasil diperbarui."}

@app.delete("/api/admin/schedule/{jid}")
def del_schedule(jid:int,u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    j=db.query(JadwalRonda).filter(JadwalRonda.id==jid).first()
    if not j: raise HTTPException(404,"Jadwal tidak ditemukan.")
    j.is_active=False; audit(db,u.id,"DEL_JADWAL",f"ID:{jid}"); db.commit()
    return {"message":"Jadwal dihapus."}

# ── ADMIN: PENGGANTI ──────────────────────────────────────
@app.get("/api/admin/pengganti")
def admin_pengganti(u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    today=date.today().isoformat()
    pgs=db.query(PenggantiRonda).filter(PenggantiRonda.tanggal>=today).order_by(PenggantiRonda.tanggal).limit(50).all(); result=[]
    for pg in pgs:
        asli=db.query(Warga).filter(Warga.id==pg.warga_asli_id).first()
        pgti=db.query(Warga).filter(Warga.id==pg.warga_pengganti_id).first()
        result.append({"id":pg.id,"tanggal":pg.tanggal,"grup_id":pg.grup_id,
                       "warga_asli":asli.nama if asli else "?","warga_asli_hp":asli.no_hp if asli else "",
                       "warga_pengganti":pgti.nama if pgti else "?","warga_pengganti_hp":pgti.no_hp if pgti else "",
                       "catatan":pg.catatan})
    return result

@app.post("/api/admin/pengganti")
def add_pengganti(tanggal:str=Form(...),grup_id:int=Form(...),warga_asli_id:int=Form(...),
                  warga_pengganti_id:int=Form(...),catatan:str=Form(""),
                  u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    asli=db.query(Warga).filter(Warga.id==warga_asli_id).first()
    pgti=db.query(Warga).filter(Warga.id==warga_pengganti_id).first()
    if not asli or not pgti: raise HTTPException(404,"Salah satu warga tidak ditemukan.")
    db.add(PenggantiRonda(tanggal=tanggal,grup_id=grup_id,warga_asli_id=asli.id,
        warga_pengganti_id=pgti.id,catatan=catatan,disetujui_oleh=u.id))
    push_notif(db,"system","📋 Jadwal Pengganti",f"Anda menggantikan {asli.nama} pada {tanggal}",warga_id=pgti.id)
    audit(db,u.id,"ADD_PENGGANTI",f"{pgti.nama} gantikan {asli.nama} tgl {tanggal}"); db.commit()
    return {"message":f"{pgti.nama} menggantikan {asli.nama} pada {tanggal}."}

@app.delete("/api/admin/pengganti/{pid}")
def del_pengganti(pid:int,u:Warga=Depends(require_admin),db:Session=Depends(get_db)):
    pg=db.query(PenggantiRonda).filter(PenggantiRonda.id==pid).first()
    if not pg: raise HTTPException(404,"Tidak ditemukan.")
    db.delete(pg); audit(db,u.id,"DEL_PENGGANTI",f"ID:{pid}"); db.commit()
    return {"message":"Data pengganti dihapus."}

SKPYEOF
info "main.py v6.10.0 siap"

section "GENERATE: Frontend PWA (index.html)"
cat > "$APP_DIR/index.html" << 'SKHTMLEOF'
<!DOCTYPE html>
<html lang="id" data-theme="light">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="theme-color" id="tc" content="#6366f1">
<meta name="apple-mobile-web-app-capable" content="yes">
<title>Siskamling Digital</title>
<link rel="manifest" href="/static/manifest.json">
<script src="https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js"></script>
<style>
:root{
  --p:#6366f1;--pd:#4f46e5;--pl:#818cf8;--pa:rgba(99,102,241,.12);
  --ok:#10b981;--er:#f43f5e;--wa:#f59e0b;--cy:#06b6d4;--pu:#8b5cf6;
  --bg:#f8fafc;--bg2:#f1f5f9;--bg3:#e2e8f0;
  --card:#fff;--tx:#0f172a;--tx2:#64748b;--tx3:#94a3b8;
  --brd:#e2e8f0;--brd2:rgba(0,0,0,.05);
  --s1:0 1px 3px rgba(0,0,0,.06);--s2:0 4px 12px rgba(0,0,0,.08);--s3:0 20px 40px rgba(0,0,0,.12);
  --r:16px;--r2:12px;--rp:50px;
  --nh:64px;--hh:56px;
  --spring:cubic-bezier(.34,1.56,.64,1);--ease:cubic-bezier(.4,0,.2,1)
}
[data-theme=dark]{
  --bg:#0f172a;--bg2:#1e293b;--bg3:#334155;
  --card:#1e293b;--tx:#f1f5f9;--tx2:#94a3b8;--tx3:#64748b;
  --brd:#334155;--brd2:rgba(255,255,255,.06);
  --s2:0 4px 12px rgba(0,0,0,.4);--s3:0 20px 40px rgba(0,0,0,.5)
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;margin:0;padding:0}
html,body{height:100%;overflow-x:hidden}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;
  background:var(--bg);color:var(--tx);
  padding-bottom:var(--nh);padding-top:var(--hh);
  font-size:15px;-webkit-font-smoothing:antialiased}

/* ── App Bar ── */
.appbar{position:fixed;top:0;inset-inline:0;height:var(--hh);z-index:200;
  background:var(--p);display:flex;align-items:center;justify-content:space-between;
  padding:0 12px;gap:8px}
.ab-title{color:#fff;font-size:.95rem;font-weight:800;display:flex;align-items:center;
  gap:8px;min-width:0;flex:1}
.ab-title span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ab-acts{display:flex;gap:4px;flex-shrink:0}
.abtn{background:rgba(255,255,255,.15);border:none;color:#fff;
  width:36px;height:36px;border-radius:50%;cursor:pointer;
  display:flex;align-items:center;justify-content:center;
  font-size:.9rem;transition:.2s;position:relative;flex-shrink:0}
.abtn:hover{background:rgba(255,255,255,.28)}
.abtn:active{transform:scale(.88)}
.abtn-badge{position:absolute;top:-3px;right:-3px;background:var(--er);color:#fff;
  font-size:.55rem;font-weight:800;border-radius:10px;padding:1px 4px;
  min-width:16px;text-align:center;line-height:1.4;display:none;
  border:2px solid var(--p)}

/* ── Container ── */
.con{padding:12px;max-width:600px;margin:0 auto;width:100%}
@media(min-width:640px){.con{padding:16px}}

/* ── Cards ── */
.card{background:var(--card);border-radius:var(--r);padding:16px;margin-bottom:10px;
  box-shadow:var(--s2);border:1px solid var(--brd2);transition:background .3s}
.card-hero{background:linear-gradient(135deg,var(--pd),var(--p));color:#fff;
  position:relative;overflow:hidden}
.card-hero::after{content:'';position:absolute;inset:0;
  background:radial-gradient(circle at 80% -10%,rgba(255,255,255,.15),transparent 55%);
  pointer-events:none}
.ct{font-size:.75rem;font-weight:800;color:var(--tx2);letter-spacing:.06em;
  text-transform:uppercase;margin-bottom:12px}

/* ── Fields ── */
.field{position:relative;margin-bottom:10px}
.field input,.field select,.field textarea{
  width:100%;padding:18px 14px 7px;border-radius:var(--r2);
  border:1.5px solid var(--brd);font-size:.88rem;font-family:inherit;
  background:var(--bg);color:var(--tx);transition:.2s;outline:none;-webkit-appearance:none}
.field textarea{min-height:72px;resize:vertical;padding-top:18px}
.field input:focus,.field select:focus,.field textarea:focus{
  border-color:var(--p);background:var(--card);box-shadow:0 0 0 3px var(--pa)}
.field label{position:absolute;left:14px;top:50%;transform:translateY(-50%);
  font-size:.85rem;color:var(--tx2);pointer-events:none;transition:.2s;font-weight:500}
.field textarea~label{top:18px;transform:none}
.field input:focus~label,.field input:not(:placeholder-shown)~label,
.field select:focus~label,.field textarea:focus~label,.field textarea:not(:placeholder-shown)~label,
.field select:not([value=''])~label{top:7px;font-size:.65rem;color:var(--p);font-weight:700;letter-spacing:.05em}
.date-wrap{position:relative;margin-bottom:10px}
.date-wrap .field{margin:0}
.date-wrap input[type=text]{padding-right:46px}
.date-wrap input[type=date]{position:absolute;opacity:0;width:0;height:0;pointer-events:none}
.cal-btn{position:absolute;right:6px;top:50%;transform:translateY(-50%);
  background:var(--pa);border:none;width:32px;height:32px;border-radius:8px;
  display:flex;align-items:center;justify-content:center;cursor:pointer;
  font-size:.85rem;color:var(--p);transition:.2s}
.cal-btn:hover{background:var(--p);color:#fff}
.field-row{display:grid;grid-template-columns:1fr 1fr;gap:8px}

/* ── Buttons ── */
.btn{display:flex;align-items:center;justify-content:center;gap:7px;
  width:100%;padding:12px 18px;border-radius:var(--rp);border:none;
  font-size:.88rem;font-weight:700;cursor:pointer;transition:.2s var(--ease);letter-spacing:-.1px}
.btn:active{transform:scale(.97)}.btn:disabled{opacity:.5;cursor:not-allowed;transform:none}
.btn-p{background:var(--p);color:#fff;box-shadow:0 4px 12px rgba(99,102,241,.3)}
.btn-p:hover{background:var(--pd)}
.btn-ok{background:var(--ok);color:#fff;box-shadow:0 4px 12px rgba(16,185,129,.25)}
.btn-er{background:var(--er);color:#fff;box-shadow:0 4px 12px rgba(244,63,94,.25)}
.btn-wa{background:var(--wa);color:#000}
.btn-cy{background:var(--cy);color:#fff}
.btn-pu{background:var(--pu);color:#fff}
.btn-o{background:transparent;border:2px solid var(--p);color:var(--p)}
.btn-o:hover{background:var(--pa)}
.btn-ghost{background:var(--bg2);color:var(--tx);border:1px solid var(--brd)}
.btn-ghost:hover{background:var(--bg3)}
.btn-sm{padding:8px 14px;font-size:.78rem;width:auto;border-radius:var(--rp)}
.btn-xs{padding:5px 10px;font-size:.72rem;width:auto;border-radius:8px;font-weight:700}
.btn-sos{background:linear-gradient(135deg,#dc2626,#ef4444);color:#fff;
  padding:18px;border-radius:14px;font-size:.95rem;font-weight:800;
  animation:sos-pulse 2.5s ease-in-out infinite}
@keyframes sos-pulse{0%,100%{box-shadow:0 4px 20px rgba(239,68,68,.4)}50%{box-shadow:0 6px 32px rgba(239,68,68,.65),0 0 0 6px rgba(239,68,68,.1)}}
.btn-pin{background:linear-gradient(135deg,var(--ok),#059669);color:#fff;
  padding:20px;border-radius:16px;font-size:1rem;font-weight:900;
  box-shadow:0 6px 24px rgba(16,185,129,.35);transition:.25s var(--spring)}
.btn-pin:active{transform:scale(.96)}

/* ── Bottom Nav ── */
.bnav{position:fixed;bottom:0;inset-inline:0;height:var(--nh);background:var(--card);
  display:flex;justify-content:space-around;align-items:center;
  border-top:1px solid var(--brd);z-index:200;
  padding-bottom:env(safe-area-inset-bottom,0px)}
.ni{display:flex;flex-direction:column;align-items:center;gap:2px;flex:1;
  padding:6px 2px;cursor:pointer;color:var(--tx3);position:relative;
  border:none;background:none;transition:.2s;min-width:0}
.ni .ic{font-size:1.35rem;transition:transform .3s var(--spring)}
.ni .lb{font-size:.6rem;font-weight:700;letter-spacing:.03em;white-space:nowrap}
.ni.active{color:var(--p)}.ni.active .ic{transform:scale(1.2)}
.ni-pill{position:absolute;top:5px;width:34px;height:34px;border-radius:50%;
  background:var(--pa);z-index:-1;transition:.3s var(--ease);opacity:0;transform:scale(0)}
.ni.active .ni-pill{opacity:1;transform:scale(1)}
.ni-badge{position:absolute;top:3px;right:calc(50% - 22px);background:var(--er);color:#fff;
  font-size:.55rem;font-weight:800;border-radius:10px;padding:1px 5px;min-width:16px;text-align:center}

/* ── Views ── */
.view{display:none;animation:slide-up .28s var(--ease) both}
.view.active{display:block}
@keyframes slide-up{from{opacity:0;transform:translateY(8px) scale(.995)}to{opacity:1;transform:none}}
.card,.wi,.cp-row,.group-card{animation:card-in .22s var(--ease) both}
@keyframes card-in{from{opacity:0;transform:translateY(5px)}to{opacity:1;transform:none}}
.app-progress{position:fixed;top:0;left:0;height:3px;width:100%;z-index:10000;pointer-events:none;opacity:0;overflow:hidden}
.app-progress.show{opacity:1}.app-progress::after{content:"";display:block;height:100%;width:38%;background:linear-gradient(90deg,var(--cy),#fff,var(--p));box-shadow:0 0 12px var(--p);animation:progress-run .7s ease-in-out infinite}
@keyframes progress-run{from{transform:translateX(-110%)}to{transform:translateX(370%)}}
button.busy{pointer-events:none;opacity:.72}button.busy::before{content:"";width:13px;height:13px;border:2px solid currentColor;border-right-color:transparent;border-radius:50%;animation:sp .55s linear infinite}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;scroll-behavior:auto!important;transition-duration:.01ms!important}}

/* ── Stats ── */
.sg{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px}
.sc{background:var(--card);border-radius:13px;padding:13px 10px;box-shadow:var(--s2);text-align:center;transition:.2s}
.sc:hover{transform:translateY(-1px);box-shadow:var(--s3)}
.sn{font-size:1.8rem;font-weight:900;line-height:1;
  background:linear-gradient(135deg,var(--pd),var(--pl));
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.sn-red{background:linear-gradient(135deg,#dc2626,#f43f5e);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.sl{font-size:.65rem;color:var(--tx2);margin-top:4px;font-weight:700;text-transform:uppercase;letter-spacing:.05em}

/* ── Chips ── */
.chip{display:inline-flex;align-items:center;gap:6px;padding:7px 13px;
  border-radius:var(--rp);font-size:.8rem;font-weight:700;margin-bottom:10px;
  animation:chip-in .3s var(--spring)}
@keyframes chip-in{from{opacity:0;transform:scale(.9)}to{opacity:1;transform:none}}
.chip-ok{background:#d1fae5;color:#065f46}
.chip-wa{background:#fef3c7;color:#92400e}
.chip-n{background:var(--bg2);color:var(--tx2)}

/* ── Avatar helper ── */
.av{width:40px;height:40px;border-radius:50%;background:linear-gradient(135deg,var(--pd),var(--pl));
  display:flex;align-items:center;justify-content:center;
  color:#fff;font-weight:800;flex-shrink:0;overflow:hidden}
.av img{width:100%;height:100%;object-fit:cover;border-radius:50%}

/* ── Photo Upload ── */
.photo-box{border:2px dashed var(--brd);border-radius:var(--r2);padding:18px;
  text-align:center;cursor:pointer;transition:.25s;background:var(--bg);margin-bottom:10px}
.photo-box:hover,.photo-box.has{border-color:var(--p);background:var(--pa)}
.photo-box.has{border-style:solid;border-color:var(--ok);background:rgba(16,185,129,.05)}
.patrol-preview{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px;margin-top:8px}
.patrol-preview:empty{display:none}
.patrol-preview img{width:100%;aspect-ratio:1/1;object-fit:cover;border-radius:9px;background:var(--bg2)}
.route-progress{height:9px;background:var(--bg3);border-radius:99px;overflow:hidden;margin:9px 0 12px}
.route-progress>span{display:block;height:100%;width:0;background:linear-gradient(90deg,var(--ok),var(--cy));
  border-radius:inherit;transition:width .45s var(--ease)}
.route-step{display:flex;align-items:flex-start;gap:10px;padding:10px 8px;border-left:3px solid var(--brd);
  margin-left:12px;position:relative;transition:.22s}
.route-step:before{content:"";position:absolute;left:-8px;top:14px;width:12px;height:12px;border-radius:50%;
  background:var(--bg3);border:2px solid var(--card)}
.route-step.selesai{border-color:var(--ok)}.route-step.selesai:before{background:var(--ok)}
.route-step.berikutnya{border-color:var(--wa);background:rgba(245,158,11,.07);border-radius:0 10px 10px 0}
.route-step.berikutnya:before{background:var(--wa);box-shadow:0 0 0 5px rgba(245,158,11,.14)}
.push-panel{background:var(--bg);border:1px solid var(--brd);border-radius:var(--r2);padding:11px;margin-bottom:11px}

/* ── Toast ── */
#toast{position:fixed;top:64px;left:50%;transform:translateX(-50%) translateY(-8px);
  color:#fff;padding:11px 20px;border-radius:var(--rp);font-weight:700;z-index:9999;
  display:none;font-size:.85rem;box-shadow:var(--s3);text-align:center;
  width:min(90vw,380px);backdrop-filter:blur(10px)}
#toast.show{display:block;animation:toast-in .32s var(--spring)}
@keyframes toast-in{from{opacity:0;transform:translateX(-50%) translateY(-20px)}
  to{opacity:1;transform:translateX(-50%) translateY(0)}}

/* ── Modals ── */
.mo{display:none;position:fixed;inset:0;background:rgba(0,0,0,.45);z-index:500;
  backdrop-filter:blur(4px);align-items:flex-end;justify-content:center}
.mo.open{display:flex;animation:mo-in .2s ease}
@keyframes mo-in{from{opacity:0}to{opacity:1}}
.mb{background:var(--card);border-radius:22px 22px 0 0;
  padding:20px 16px;padding-bottom:calc(20px + env(safe-area-inset-bottom,0px));
  width:100%;max-width:600px;max-height:90vh;overflow-y:auto;animation:mb-in .32s var(--spring)}
@keyframes mb-in{from{transform:translateY(100%)}to{transform:none}}
.mb-handle{width:36px;height:4px;border-radius:2px;background:var(--bg3);margin:0 auto 16px}
.mb-title{font-size:1rem;font-weight:800;margin-bottom:14px}
.btn-close{background:var(--bg2);border:none;width:30px;height:30px;border-radius:50%;
  cursor:pointer;display:flex;align-items:center;justify-content:center;
  font-size:.8rem;color:var(--tx2);transition:.2s;flex-shrink:0}
.btn-close:hover{background:var(--bg3)}

/* ── Result Modal ── */
.result-mo .mb{text-align:center;padding:28px 20px}
.result-icon{font-size:3.5rem;margin-bottom:12px}
.result-title{font-size:1.2rem;font-weight:900;margin-bottom:8px}
.result-msg{font-size:.88rem;color:var(--tx2);line-height:1.6;margin-bottom:20px;white-space:pre-line}

/* ── SOS Alert Popup ── */
.sos-popup{position:fixed;inset:0;z-index:600;
  background:rgba(220,38,38,.88);backdrop-filter:blur(6px);
  display:flex;align-items:center;justify-content:center;animation:chip-in .3s ease}
.sos-box{background:#fff;border-radius:20px;padding:28px 20px;
  max-width:320px;width:90%;text-align:center;box-shadow:var(--s3)}

/* ── Notification Panel ── */
.notif-item{padding:11px 12px;background:var(--bg);border-radius:var(--r2);margin-bottom:7px;
  border-left:3px solid var(--p);position:relative}
.notif-item.sos{border-color:var(--er);background:rgba(244,63,94,.06)}
.notif-item.unread{background:var(--card);box-shadow:var(--s1)}
.notif-del{position:absolute;top:8px;right:8px;background:none;border:none;
  color:var(--tx3);cursor:pointer;font-size:.8rem;padding:4px;transition:.2s;border-radius:6px}
.notif-del:hover{color:var(--er);background:rgba(244,63,94,.1)}

/* ── Group Sub-tabs ── */
.gtabs{display:flex;gap:5px;margin-bottom:12px;background:var(--bg2);
  border-radius:var(--rp);padding:3px}
.gtab{flex:1;padding:8px 4px;border-radius:var(--rp);font-size:.76rem;font-weight:700;
  cursor:pointer;border:none;background:transparent;color:var(--tx2);transition:.2s;
  white-space:nowrap}
.gtab.active{background:var(--card);color:var(--p);box-shadow:var(--s1)}

/* ── Member Cards ── */
.member-card{display:flex;align-items:center;gap:10px;padding:10px;
  background:var(--bg);border-radius:var(--r2);margin-bottom:7px;transition:.2s}
.member-card:hover{background:var(--card)}
.m-dot{width:9px;height:9px;border-radius:50%;flex-shrink:0}
.m-dot.in{background:var(--ok)}.m-dot.out{background:var(--er)}.m-dot.belum{background:var(--tx3)}

/* ── CHAT ── */
.chat-wrapper{display:flex;flex-direction:column;
  height:calc(100dvh - var(--hh) - var(--nh) - 112px);min-height:320px;
  border-radius:var(--r);overflow:hidden;background:var(--card);box-shadow:var(--s2)}
.chat-msgs{flex:1;overflow-y:auto;padding:14px 12px;-webkit-overflow-scrolling:touch;
  scroll-behavior:smooth;overscroll-behavior:contain;min-height:0}
.chat-msgs::-webkit-scrollbar{width:2px}
.chat-msgs::-webkit-scrollbar-thumb{background:var(--brd);border-radius:2px}

/* Reply preview bar */
.reply-bar{padding:8px 12px;background:var(--bg2);border-top:1px solid var(--brd);
  display:none;align-items:center;gap:8px}
.reply-bar.show{display:flex}
.reply-preview-text{flex:1;font-size:.78rem;color:var(--tx2);
  border-left:3px solid var(--p);padding-left:8px;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.reply-cancel{background:none;border:none;color:var(--tx3);cursor:pointer;font-size:.9rem;padding:2px}

/* Chat Input */
.chat-input-bar{padding:8px 10px;background:var(--bg2);
  border-top:1px solid var(--brd);display:flex;align-items:flex-end;gap:7px;
  flex-shrink:0;position:sticky;bottom:0;z-index:5;
  padding-bottom:calc(8px + env(safe-area-inset-bottom,0px))}
.chat-inp{flex:1;padding:10px 13px;border-radius:20px;border:1.5px solid var(--brd);
  background:var(--card);color:var(--tx);font-size:.88rem;outline:none;
  font-family:inherit;resize:none;max-height:100px;min-height:40px;
  transition:.2s;line-height:1.4}
.chat-inp:focus{border-color:var(--p)}
.chat-send{background:var(--p);border:none;color:#fff;
  width:38px;height:38px;border-radius:50%;cursor:pointer;font-size:.9rem;
  display:flex;align-items:center;justify-content:center;transition:.2s;flex-shrink:0}
.chat-send:hover{background:var(--pd)}.chat-send:active{transform:scale(.9)}

/* Bubbles */
.bw{display:flex;gap:7px;margin-bottom:8px;align-items:flex-end;animation:slide-up .2s ease}
.bw.mine{flex-direction:row-reverse}
.bav{width:28px;height:28px;border-radius:50%;flex-shrink:0;overflow:hidden;
  background:linear-gradient(135deg,var(--pd),var(--pl));
  display:flex;align-items:center;justify-content:center;
  color:#fff;font-size:.68rem;font-weight:800;align-self:flex-end}
.bav img{width:100%;height:100%;object-fit:cover}
.bmeta{max-width:84%;display:flex;flex-direction:column}
.bname{font-size:.66rem;font-weight:700;color:var(--tx2);margin-bottom:2px;padding-left:2px}
.bubble{padding:9px 12px;border-radius:16px;font-size:.85rem;line-height:1.5;
  word-break:break-word;position:relative;white-space:pre-wrap}
.bubble.theirs{background:var(--card);border-radius:4px 16px 16px 16px;
  box-shadow:var(--s1);color:var(--tx)}
.bubble.mine{background:var(--p);color:#fff;border-radius:16px 4px 16px 16px}
.bubble.deleted{background:var(--bg2);color:var(--tx3);font-style:italic;
  border-radius:12px;font-size:.82rem}
.bubble.system-msg{background:transparent;color:var(--tx3);font-size:.74rem;
  text-align:center;padding:4px;box-shadow:none}
.btime{font-size:.62rem;margin-top:3px;opacity:.6;padding:0 2px}
.bw.mine .btime{text-align:right}

/* Reply in bubble */
.breply{background:rgba(0,0,0,.08);border-left:3px solid rgba(255,255,255,.5);
  border-radius:8px;padding:5px 8px;margin-bottom:6px;font-size:.76rem;opacity:.85}
.bubble.theirs .breply{background:var(--bg2);border-color:var(--p)}
.chat-media{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:4px;margin-top:7px}
.chat-media.one{grid-template-columns:1fr}
.chat-media img{display:block;width:100%;height:120px;object-fit:cover;border-radius:9px;cursor:zoom-in;background:var(--bg2)}
.chat-media.one img{height:auto;max-height:280px}
.photo-viewer{position:fixed;inset:0;z-index:10000;background:rgba(4,8,20,.94);display:flex;
  align-items:center;justify-content:center;padding:18px;animation:mo-in .18s ease;cursor:zoom-out}
.photo-viewer img{max-width:100%;max-height:92vh;object-fit:contain;border-radius:10px;box-shadow:var(--s3)}
.photo-viewer button{position:absolute;top:16px;right:16px;width:42px;height:42px;border:0;border-radius:50%;
  background:rgba(255,255,255,.16);color:#fff;font-size:1.15rem;cursor:pointer}

/* Message actions */
.bactions{display:none;gap:3px;margin-top:4px}
.bw:hover .bactions,.bw:focus-within .bactions{display:flex}
.baction-btn{background:var(--bg2);border:none;border-radius:8px;padding:4px 8px;
  font-size:.7rem;cursor:pointer;color:var(--tx2);transition:.15s;display:flex;align-items:center;gap:3px}
.baction-btn:hover{background:var(--bg3);color:var(--tx)}
.baction-btn.del:hover{background:rgba(244,63,94,.1);color:var(--er)}
.bw.mine .bactions{justify-content:flex-end}

/* ── Admin Tabs ── */
.atabs{display:flex;gap:4px;overflow-x:auto;padding-bottom:8px;margin-bottom:12px;scrollbar-width:none}
.atabs::-webkit-scrollbar{display:none}
.atab{padding:7px 13px;border-radius:var(--rp);font-size:.76rem;font-weight:700;
  cursor:pointer;white-space:nowrap;border:none;background:var(--bg2);color:var(--tx2);transition:.2s}
.atab.active{background:var(--p);color:#fff;box-shadow:0 3px 10px rgba(99,102,241,.3)}

/* ── Warga Item ── */
.wi{display:flex;align-items:center;gap:10px;padding:10px;
  background:var(--bg);border-radius:var(--r2);margin-bottom:7px;transition:.2s}
.wi:hover{background:var(--card)}

/* ── Checkpoint Row ── */
.cp-row{display:flex;justify-content:space-between;align-items:center;padding:9px;
  background:var(--bg);border-radius:var(--r2);margin-bottom:7px;gap:8px;transition:.2s}
.cp-row:hover{background:var(--card)}
.admin-cp-card{background:var(--bg);border:1px solid var(--brd);border-radius:var(--r2);
  padding:12px;margin-bottom:9px;display:grid;grid-template-columns:minmax(0,1fr);gap:10px;transition:.2s}
.admin-cp-card:hover{background:var(--card);box-shadow:var(--s1)}
.admin-cp-title{display:flex;align-items:center;gap:6px;flex-wrap:wrap;min-width:0}
.admin-cp-name{font-size:.88rem;font-weight:850;line-height:1.35;overflow-wrap:anywhere}
.admin-cp-route{font-size:.7rem;font-weight:800;color:var(--p);background:var(--pa);
  border-radius:var(--rp);padding:4px 8px;white-space:nowrap}
.admin-cp-meta{font-size:.73rem;color:var(--tx2);line-height:1.55;margin-top:5px;overflow-wrap:anywhere}
.admin-cp-actions{display:grid;grid-template-columns:repeat(auto-fit,minmax(70px,1fr));gap:6px;width:100%}
.admin-cp-actions .btn{width:100%;min-width:0;min-height:36px;padding:7px 8px;white-space:nowrap}
@media(min-width:720px){
  .admin-cp-card{grid-template-columns:minmax(0,1fr) auto;align-items:center;padding:13px 14px}
  .admin-cp-actions{display:flex;width:auto}.admin-cp-actions .btn{width:auto;min-width:72px}
}

/* ── GPS Card ── */
.gps-card{background:linear-gradient(135deg,#0f766e,#0d9488);color:#fff;
  border-radius:var(--r2);padding:16px;margin-bottom:12px;text-align:center;position:relative;overflow:hidden}
.gps-icon{font-size:2.2rem;animation:gps-pulse 2s ease-in-out infinite;display:block;margin-bottom:6px}
@keyframes gps-pulse{0%,100%{transform:scale(1)}50%{transform:scale(1.1)}}

/* ── Schedule Chip ── */
.jadwal-chip{display:inline-flex;align-items:center;gap:5px;padding:6px 12px;
  border-radius:var(--rp);font-size:.78rem;font-weight:700}
.jadwal-chip.active{background:#d1fae5;color:#065f46}
.jadwal-chip.inactive{background:#fee2e2;color:#991b1b}

/* ── Divider ── */
.div{height:1px;background:var(--brd);margin:10px 0}

/* ── Badge ── */
.badge{display:inline-block;padding:2px 8px;border-radius:var(--rp);font-size:.7rem;font-weight:700;background:var(--pa);color:var(--p)}
.badge-ok{background:#d1fae5;color:#065f46}.badge-er{background:#fee2e2;color:#991b1b}
.badge-wa{background:#fef3c7;color:#92400e}.badge-ko{background:#f3e8ff;color:#6b21a8}

/* ── Loading ── */
.loading{display:flex;flex-direction:column;align-items:center;gap:10px;padding:24px;color:var(--tx3)}
.spin{width:26px;height:26px;border:2.5px solid var(--bg3);
  border-top-color:var(--p);border-radius:50%;animation:sp .7s linear infinite}
@keyframes sp{to{transform:rotate(360deg)}}

/* ── Login ── */
#view-login{background:linear-gradient(160deg,var(--pd),var(--p),#7c3aed);
  min-height:100svh;flex-direction:column;align-items:center;
  position:fixed;inset:0;z-index:10;overflow-y:auto;padding-top:var(--hh)}
#view-login.active{display:flex!important}
.login-hero{flex:1;display:flex;flex-direction:column;align-items:center;
  justify-content:center;padding:32px 20px 16px;color:#fff;text-align:center}
.login-hero .shield{font-size:3.8rem;animation:float 3s ease-in-out infinite;display:block}
@keyframes float{0%,100%{transform:translateY(0)}50%{transform:translateY(-9px)}}
.login-sheet{background:var(--card);border-radius:22px 22px 0 0;
  padding:22px 16px;width:100%;max-width:600px}

/* ── Set row ── */
.set-row{margin-bottom:12px}
.set-label{font-size:.72rem;font-weight:700;color:var(--tx2);text-transform:uppercase;letter-spacing:.06em;display:block;margin-bottom:4px}
.set-ctrl{display:flex;gap:7px;align-items:center}
.set-ctrl input{flex:1;padding:10px 12px;border-radius:var(--r2);border:1.5px solid var(--brd);
  background:var(--bg);color:var(--tx);font-size:.85rem;outline:none;font-family:inherit;margin:0;transition:.2s}
.set-ctrl input:focus{border-color:var(--p)}

/* ── Group card ── */
.group-card{background:var(--bg);border-radius:var(--r2);padding:12px;margin-bottom:8px;
  border-left:3px solid var(--p)}
.komp-alert{background:linear-gradient(135deg,rgba(245,158,11,.13),rgba(249,115,22,.08));
  border:1px solid rgba(245,158,11,.3);border-left:4px solid var(--wa);border-radius:var(--r);padding:14px;margin-bottom:10px}
.komp-row{background:var(--bg);border-radius:var(--r2);padding:11px;margin-bottom:7px;border-left:3px solid var(--wa)}

/* ── Data transfer ── */
.data-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:7px;margin:10px 0 14px}
.data-check{display:flex;align-items:center;gap:8px;padding:9px 10px;background:var(--bg);
  border:1px solid var(--brd);border-radius:10px;font-size:.78rem;font-weight:700;cursor:pointer}
.data-check input{width:17px;height:17px;accent-color:var(--p);flex-shrink:0}
.import-result{font-size:.78rem;line-height:1.55;background:var(--bg);border-radius:var(--r2);padding:11px;margin-top:10px;white-space:pre-line}

/* ── Responsive fixes ── */
@media(max-width:380px){
  .sg{grid-template-columns:1fr 1fr}
  .sn{font-size:1.6rem}
  .field-row{grid-template-columns:1fr}
  .btn{font-size:.82rem;padding:11px 14px}
  .chat-wrapper{height:calc(100dvh - var(--hh) - var(--nh) - 104px);min-height:300px}
  .bmeta{max-width:88%}
}
@media(min-width:640px) and (max-width:899px){
  .chat-wrapper{height:calc(100dvh - var(--hh) - var(--nh) - 104px);min-height:380px}
  .bnav,.appbar,#view-login{max-width:760px;left:50%;right:auto;transform:translateX(-50%)}
  .con{max-width:760px;margin:0 auto;transform:none}
  .bmeta{max-width:80%}
}
@media(min-width:900px){
  body.authenticated{padding:72px 0 24px 228px;min-height:100vh}
  body.authenticated .appbar{left:228px;height:64px;padding:0 26px;box-shadow:var(--s1)}
  body.authenticated .bnav{display:flex!important;left:0;right:auto;top:0;bottom:0;width:228px;height:100vh;
    flex-direction:column;justify-content:flex-start;align-items:stretch;gap:6px;padding:82px 14px 20px;
    border-top:0;border-right:1px solid var(--brd);box-shadow:4px 0 20px rgba(15,23,42,.04)}
  body.authenticated .ni{flex:none;width:100%;height:48px;flex-direction:row;justify-content:flex-start;
    gap:12px;padding:10px 14px;border-radius:12px;text-align:left}
  body.authenticated .ni:hover{background:var(--bg2);color:var(--tx)}
  body.authenticated .ni.active{background:var(--pa);color:var(--p)}
  body.authenticated .ni .ic{width:28px;text-align:center;font-size:1.25rem}
  body.authenticated .ni .lb{font-size:.82rem;letter-spacing:0}
  body.authenticated .ni-pill{display:none}
  body.authenticated .ni-badge{top:14px;right:14px}
  .con{max-width:1180px;padding:20px 28px;margin:0 auto}
  .sg{grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}
  .card{padding:20px;margin-bottom:14px}
  .atabs{position:sticky;top:72px;z-index:80;background:var(--bg);padding:8px 0 12px;margin-bottom:12px}
  #view-grup .con.chat-mode{max-width:1500px;padding:8px 24px 0}
  .chat-wrapper{height:calc(100vh - 142px);min-height:480px;border-radius:16px}
  .data-grid{grid-template-columns:repeat(3,minmax(0,1fr))}
  .bmeta{max-width:76%}
  .login-shell{max-width:1000px!important;min-height:620px!important;height:min(760px,90vh);flex-direction:row!important;
    margin:auto;overflow:hidden;border-radius:28px;background:var(--card);box-shadow:0 28px 70px rgba(15,23,42,.28)}
  #view-login{padding:84px 28px 28px;justify-content:center}
  .login-hero{flex:1 1 48%;padding:48px;min-height:100%}
  .login-hero .shield{font-size:5rem}
  .login-sheet{flex:1 1 52%;max-width:none;border-radius:0;padding:38px 42px;overflow-y:auto;align-self:stretch}
  .mo{align-items:center;padding:24px}.mb{border-radius:22px;max-width:640px;max-height:86vh}
}
#view-grup .con.chat-mode>.card-hero{display:none}
#view-grup .con.chat-mode>.gtabs{margin:0 4px 7px}
#view-grup .con.chat-mode{padding-top:7px}
@media(max-width:899px){
  #view-grup .con.chat-mode{max-width:100%;padding:6px 0 0}
  #view-grup .con.chat-mode>.gtabs{margin:0 8px 6px}
  #view-grup .con.chat-mode #chat-room-wrap{margin:0 8px 6px}
  #view-grup .con.chat-mode .chat-wrapper{border-radius:0;border-left:0;border-right:0}
}
@supports(padding-bottom:env(safe-area-inset-bottom)){
  .bnav{padding-bottom:env(safe-area-inset-bottom)}
  body{padding-bottom:calc(var(--nh) + env(safe-area-inset-bottom))}
}
</style>
</head>
<body>

<!-- ══ APP BAR ══ -->
<div class="appbar" id="appbar">
  <div class="ab-title"><span>🛡️</span><span id="app-title">Siskamling</span></div>
  <div class="ab-acts">
    <button class="abtn" onclick="toggleDark()" id="btn-dark" title="Mode Gelap">🌙</button>
    <button class="abtn" onclick="openNotifPanel()" id="btn-notif" style="display:none" title="Notifikasi">
      🔔<span class="abtn-badge" id="notif-badge"></span>
    </button>
    <button class="abtn" id="btn-logout" style="display:none" onclick="confirmLogout()" title="Keluar">🚪</button>
  </div>
</div>

<div id="toast"></div>
<div id="app-progress" class="app-progress" aria-hidden="true"></div>

<!-- ══ LOGIN ══ -->
<div id="view-login" class="view">
  <div class="login-shell" style="max-width:600px;width:100%;display:flex;flex-direction:column;min-height:100svh">
    <div class="login-hero">
      <span class="shield">🛡️</span>
      <h1 id="lkn" style="font-size:1.4rem;font-weight:900;margin:10px 0 5px">Siskamling Digital</h1>
      <p style="opacity:.8;font-size:.85rem;margin-bottom:12px">Sistem Keamanan Lingkungan</p>
      <div id="login-badge" style="background:rgba(255,255,255,.15);color:#fff;padding:6px 14px;
           border-radius:var(--rp);font-size:.75rem;font-weight:700;border:1px solid rgba(255,255,255,.2)">
        ✨ Daftarkan Perangkat Baru
      </div>
    </div>
    <div class="login-sheet">
      <div class="mb-handle"></div>
      <div class="gtabs" style="margin-bottom:14px">
        <button class="gtab active" id="login-mode-btn" type="button" onclick="setLoginMode(false)">🔐 Login</button>
        <button class="gtab" id="setup-mode-btn" type="button" onclick="setLoginMode(true)">✨ Aktivasi / Buat Password</button>
      </div>
      <p id="login-help" style="font-size:.82rem;color:var(--tx2);margin-bottom:14px;line-height:1.6">Masukkan <b>ID akun (contoh WG00001) atau No. HP</b> dan password.</p>
      <div class="field"><input type="text" id="inp-identifier" placeholder=" " autocomplete="username" autocapitalize="characters" oninput="this.value=this.value.toUpperCase()"><label>ID Akun / Nomor Handphone</label></div>
      <div class="field" id="login-password-row"><input type="password" id="inp-password" placeholder=" " autocomplete="current-password"><label>Password</label></div>
      <div id="activation-fields" style="display:none">
      <div class="date-wrap">
        <div class="field"><input type="text" id="inp-lahir" placeholder=" " inputmode="numeric" maxlength="10" oninput="fmtDate(this)" style="padding-right:46px"><label>Tanggal Lahir (DD-MM-YYYY)</label></div>
        <input type="date" id="date-pick-login" onchange="applyDate(this.value,'inp-lahir')">
        <button class="cal-btn" type="button" onclick="openCal('date-pick-login','inp-lahir')">📅</button>
      </div>
      <div class="field"><input type="password" id="inp-new-password" placeholder=" " autocomplete="new-password"><label>Password Baru (min. 6, huruf + angka)</label></div>
      <div class="field"><input type="password" id="inp-confirm-password" placeholder=" " autocomplete="new-password"><label>Ulangi Password Baru</label></div>
      <div id="photo-section">
        <div class="div" style="margin:14px 0 10px"><span style="font-size:.7rem;color:var(--tx3);font-weight:700">FOTO WAJAH (PERANGKAT BARU)</span></div>
        <div class="photo-box" id="photo-box" onclick="document.getElementById('inp-foto').click()">
          <div id="photo-ph"><div style="font-size:2rem;margin-bottom:4px">🤳</div>
            <b style="font-size:.85rem">Tap untuk Selfie / Upload</b>
            <div style="font-size:.72rem;color:var(--tx2);margin-top:2px">JPG/PNG · Auto-kompres otomatis</div>
          </div>
          <img id="photo-prev" style="display:none;width:76px;height:76px;border-radius:50%;object-fit:cover;margin:0 auto">
        </div>
        <input type="file" id="inp-foto" accept="image/*" capture="user" style="display:none" onchange="prevPhoto(this)">
      </div>
      </div>
      <button class="btn btn-p" id="btn-login" onclick="doLogin()">🔐 Masuk</button>
      <p style="text-align:center;font-size:.72rem;color:var(--tx3);margin-top:10px">Belum terdaftar? Hubungi Koordinator atau Admin.</p>
    </div>
  </div>
</div>

<!-- ══ BERANDA ══ -->
<div id="view-home" class="view">
  <div class="con">
    <div class="card card-hero">
      <div style="font-size:1rem;font-weight:900" id="greet">Halo! 👋</div>
      <div style="font-size:.78rem;opacity:.85;margin-top:4px;display:flex;gap:7px;align-items:center;flex-wrap:wrap">
        <span id="rbadge" class="badge" style="background:rgba(255,255,255,.2);color:#fff"></span>
        <span id="gbadge" style="opacity:.9"></span>
      </div>
    </div>
    <div id="absen-home"></div>
    <div id="jadwal-home"></div>
    <div id="kompensasi-home"></div>
    <div class="sg">
      <div class="sc"><div class="sn" id="sw">–</div><div class="sl">Total Warga</div></div>
      <div class="sc"><div class="sn" id="sa">–</div><div class="sl">Absen Hari Ini</div></div>
      <div class="sc"><div class="sn" id="sp">–</div><div class="sl">Patroli Hari Ini</div></div>
      <div class="sc"><div class="sn sn-red" id="se">–</div><div class="sl">Alert SOS</div></div>
    </div>
    <div class="card"><div class="ct">⏰ Jadwal Ronda</div><p id="jam-info" style="color:var(--tx2);font-size:.9rem">Memuat...</p></div>
    <div class="card" style="background:var(--bg)">
      <button class="btn btn-sos" onclick="openMo('mo-sos')">🆘&nbsp; TOMBOL DARURAT / SOS</button>
      <p style="text-align:center;font-size:.7rem;color:var(--tx3);margin-top:8px;line-height:1.5">Tekan jika situasi darurat nyata. GPS Anda dikirim ke Tim Ronda.</p>
    </div>
  </div>
</div>

<!-- ══ ABSENSI ══ -->
<div id="view-absen" class="view">
  <div class="con">
    <div class="card">
      <div class="ct">📲 Absensi QR Code</div>
      <div id="absen-inline"></div>
      <button class="btn btn-o" id="btn-scan-absen" onclick="toggleQR('absen')" style="margin-bottom:9px">📷 Buka Kamera QR Scanner</button>
      <div id="qr-reader-absen" style="display:none;border-radius:var(--r2);overflow:hidden;background:#000;margin-bottom:10px"></div>
      <div id="qrr-absen" style="display:none;background:var(--bg);border:2px solid var(--ok);border-radius:10px;padding:9px 13px;margin-bottom:10px;font-weight:700;color:var(--ok);font-size:.83rem"></div>
      <div class="field"><input type="text" id="inp-qr-absen" placeholder=" " style="text-transform:uppercase" autocomplete="off"><label>Token QR (masukkan manual jika scan gagal)</label></div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
        <button class="btn btn-ok" onclick="doCheckin()">✅ Check-IN<br><span style="font-size:.72rem;font-weight:400;opacity:.85">Mulai Ronda</span></button>
        <button class="btn btn-er" onclick="doCheckout()">🚩 Check-OUT<br><span style="font-size:.72rem;font-weight:400;opacity:.85">Selesai Ronda</span></button>
      </div>
    </div>
    <div class="card"><div class="ct">📋 Pos Absensi</div>
      <p style="font-size:.78rem;color:var(--tx2);margin-bottom:8px">Scan QR di pos atau ketik token di atas.</p>
      <div id="cp-absen"><div class="loading"><div class="spin"></div></div></div>
    </div>
  </div>
</div>

<!-- ══ PATROLI GPS PIN ══ -->
<div id="view-patrol" class="view">
  <div class="con">
    <div class="card" id="patrol-route-card">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px">
        <div class="ct" style="margin:0">🧭 Rute Patroli Grup</div>
        <button class="btn btn-xs btn-ghost" onclick="loadPatrolRoute()">🔄</button>
      </div>
      <div id="patrol-route"><div class="loading"><div class="spin"></div></div></div>
    </div>
    <div class="card">
      <div class="ct">📍 Laporan Patroli — Pin Lokasi</div>
      <p style="font-size:.82rem;color:var(--tx2);margin-bottom:14px;line-height:1.5">Tap tombol di bawah untuk menandai lokasi GPS Anda secara otomatis. Tidak perlu QR Code.</p>
      <div id="gps-idle" style="text-align:center;padding:16px 0">
        <div style="font-size:3rem;opacity:.25;margin-bottom:8px">📍</div>
        <p style="color:var(--tx2);font-size:.85rem">Lokasi belum ditandai</p>
      </div>
      <div id="gps-result" style="display:none" class="gps-card">
        <span class="gps-icon">📍</span>
        <div id="gps-cp-name" style="font-weight:900;font-size:.95rem">Mendeteksi...</div>
        <div id="gps-coords-text" style="font-size:.75rem;opacity:.9;margin-top:3px;font-family:monospace"></div>
        <div id="gps-dist" style="font-size:.76rem;opacity:.8;margin-top:2px"></div>
      </div>
      <button class="btn btn-pin" id="btn-pin-loc" onclick="pinLocation()">📍&nbsp; TANDAI LOKASI SAYA</button>
      <div id="patrol-form" style="display:none;margin-top:14px">
        <div class="div"></div>
        <div class="field" id="manual-pos-wrap" style="display:none">
          <select id="manual-pos"><option value="">Laporan lokasi umum</option></select>
          <label>Pos Patroli (jika GPS tidak mendeteksi)</label>
        </div>
        <p id="manual-pos-help" style="display:none;font-size:.72rem;color:var(--tx2);line-height:1.45;margin:-5px 2px 11px">Pilih pos terdaftar jika GPS kurang akurat. Server tetap memeriksa jaraknya.</p>
        <div class="field"><textarea id="inp-ket" placeholder=" " rows="3"></textarea><label>Keterangan Situasi</label></div>
        <div class="photo-box" id="pbox" onclick="document.getElementById('inp-photo').click()">
          <div id="plabel"><div style="font-size:1.5rem;margin-bottom:3px">📷</div><b style="font-size:.83rem">Foto Lokasi (Opsional, Maks. 6)</b><div style="font-size:.7rem;color:var(--tx2);margin-top:3px">Bisa pilih beberapa foto sekaligus</div></div>
          <div id="pprev-grid" class="patrol-preview"></div>
        </div>
        <input type="file" id="inp-photo" accept="image/jpeg,image/png,image/webp" multiple style="display:none" onchange="prevPatrol(this)">
        <button class="btn btn-wa" id="btn-patrol-submit" onclick="doPatrolGPS()">📤 Kirim Laporan</button>
        <button class="btn btn-ghost" onclick="resetPatrol()" style="margin-top:7px">🔄 Ulang Lokasi</button>
      </div>
    </div>
    <div class="card"><div class="ct">📌 Pos Patroli (Referensi)</div>
      <div id="cp-patrol"><div class="loading"><div class="spin"></div></div></div>
    </div>
  </div>
</div>

<!-- ══ GRUP ══ -->
<div id="view-grup" class="view">
  <div class="con">
    <div class="card card-hero" style="margin-bottom:10px;padding:14px 16px">
      <div style="font-size:1rem;font-weight:900">👥 <span id="grup-nama-title">Grup Ronda</span></div>
      <div style="font-size:.78rem;opacity:.85;margin-top:3px" id="grup-jadwal-badge"></div>
    </div>
    <div class="gtabs">
      <button class="gtab active" onclick="gTab('anggota',this)">👥 Anggota</button>
      <button class="gtab" onclick="gTab('chat',this)">💬 Chat</button>
      <button class="gtab" onclick="gTab('jadwal',this)">📅 Jadwal</button>
      <button class="gtab" id="gtab-kompensasi" style="display:none" onclick="gTab('kompensasi',this)">💳 Kompensasi</button>
    </div>

    <!-- Anggota -->
    <div id="gsub-anggota">
      <button class="btn btn-ghost btn-sm" onclick="loadMembers()" style="margin-bottom:10px">🔄 Perbarui</button>
      <div id="member-list"><div class="loading"><div class="spin"></div></div></div>
    </div>

    <!-- Chat -->
    <div id="gsub-chat" style="display:none">
      <div class="field" id="chat-room-wrap" style="display:none"><select id="chat-room" onchange="switchChatRoom(this.value)"></select></div>
      <div class="chat-wrapper">
        <div class="chat-msgs" id="chat-msgs">
          <div class="loading"><div class="spin"></div></div>
        </div>
        <div class="reply-bar" id="reply-bar">
          <div class="reply-preview-text" id="reply-preview-text">...</div>
          <button class="reply-cancel" onclick="cancelReply()">✕</button>
        </div>
        <div class="chat-input-bar">
          <textarea class="chat-inp" id="chat-inp" placeholder="Ketik pesan..." rows="1"
            oninput="autoResize(this)" onkeypress="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();sendChat()}"></textarea>
          <button class="chat-send" onclick="sendChat()">➤</button>
        </div>
      </div>
      <div id="invite-section" style="display:none;margin-top:10px">
        <div class="card"><div class="ct">📨 Undangan Masuk</div><div id="invite-list"></div></div>
      </div>
      <div class="card" id="invite-manager-card" style="display:none;margin-top:10px">
        <div class="ct">➕ Undang Warga ke Chat</div>
        <p style="font-size:.78rem;color:var(--tx2);margin-bottom:8px">Undang warga dari grup lain untuk melihat chat ini.</p>
        <div class="field"><input type="text" id="invite-hp" placeholder=" " autocapitalize="characters" oninput="this.value=this.value.toUpperCase()"><label>ID Akun / No. HP yang Diundang</label></div>
        <button class="btn btn-pu" onclick="sendInvite()">📨 Kirim Undangan</button>
      </div>
    </div>

    <!-- Jadwal -->
    <div id="gsub-jadwal" style="display:none">
      <div class="card"><div class="ct">📅 Jadwal Ronda Grup Saya</div>
        <div id="jadwal-list"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>

    <div id="gsub-kompensasi" style="display:none">
      <div class="card"><div class="ct">💳 Tagihan Kompensasi Grup</div>
        <p style="font-size:.78rem;color:var(--tx2);line-height:1.5;margin-bottom:9px">Koordinator dapat memverifikasi pembayaran warga pada grupnya.</p>
        <div class="field"><select id="group-komp-status" onchange="loadKompensasi('group-komp-list','group')"><option value="belum">Belum Dibayar</option><option value="lunas">Sudah Lunas</option><option value="dibatalkan">Dibatalkan</option><option value="all">Semua Status</option></select></div>
        <button class="btn btn-ghost btn-sm" onclick="exportKompensasi('group')" style="margin-bottom:10px">📊 Unduh Laporan Excel</button>
        <div id="group-komp-list"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>
  </div>
</div>

<!-- ══ ADMIN ══ -->
<div id="view-admin" class="view">
  <div class="con">
    <div class="card card-hero" style="margin-bottom:10px;padding:14px 16px">
      <div style="font-size:1rem;font-weight:900">👑 Panel Pengurus</div>
      <div style="font-size:.78rem;opacity:.8;margin-top:2px">Kelola data siskamling</div>
    </div>
    <div class="atabs">
      <button class="atab active" onclick="aTab('adash',this)">📊 Statistik</button>
      <button class="atab" onclick="aTab('awarga',this)">👥 Warga</button>
      <button class="atab" onclick="aTab('aabsen',this)">📝 Absensi</button>
      <button class="atab" onclick="aTab('agrup',this)">🏘️ Grup</button>
      <button class="atab" onclick="aTab('acp',this)">📌 Checkpoint</button>
      <button class="atab" onclick="aTab('aset',this)">⚙️ Pengaturan</button>
      <button class="atab" onclick="aTab('ajadwal',this)">📅 Jadwal</button>
      <button class="atab" onclick="aTab('apengganti',this)">🔄 Pengganti</button>
      <button class="atab" onclick="aTab('akompensasi',this)">💳 Kompensasi</button>
      <button class="atab" onclick="aTab('adata',this)">⇄ Data</button>
      <button class="atab" onclick="aTab('alap',this)">📁 Laporan</button>
      <button class="atab" onclick="aTab('asos',this)">🆘 SOS</button>
      <button class="atab" onclick="aTab('alog',this)">🔍 Log</button>
    </div>

    <div id="adash">
      <div class="sg" id="adsg"><div class="loading" style="grid-column:1/-1"><div class="spin"></div></div></div>
      <button class="btn btn-ghost btn-sm" onclick="loadAdminStats()">🔄 Perbarui</button>
    </div>

    <div id="awarga" style="display:none">
      <div class="card"><div class="ct">➕ Tambah Warga</div>
        <div class="field"><input type="text" id="nw-nama" placeholder=" "><label>Nama Lengkap *</label></div>
        <div class="field"><input type="text" id="nw-aid" placeholder=" " maxlength="7" autocapitalize="characters" oninput="this.value=this.value.toUpperCase()"><label>ID Akun 7 Karakter (kosong = otomatis)</label></div>
        <div class="field"><input type="tel" id="nw-hp" placeholder=" " inputmode="numeric"><label>No. Handphone *</label></div>
        <div class="date-wrap">
          <div class="field"><input type="text" id="nw-lahir" placeholder=" " inputmode="numeric" maxlength="10" oninput="fmtDate(this)" style="padding-right:46px"><label>Tanggal Lahir (DD-MM-YYYY) *</label></div>
          <input type="date" id="nw-datepick" onchange="applyDate(this.value,'nw-lahir')">
          <button class="cal-btn" type="button" onclick="openCal('nw-datepick','nw-lahir')">📅</button>
        </div>
        <div class="field-row">
          <div class="field" style="margin:0"><input type="number" id="nw-grup" placeholder=" " min="1"><label>Nomor Grup *</label></div>
          <div class="field" style="margin:0"><select id="nw-role"><option value="">Pilih Role</option>
            <option value="warga">Warga</option><option value="koordinator">Koordinator</option>
            <option value="admin">Admin</option></select></div>
        </div>
        <div class="field"><input type="text" id="nw-cat" placeholder=" "><label>Catatan</label></div>
        <button class="btn btn-ok" onclick="addWarga()">✅ Daftarkan Warga</button>
      </div>
      <div class="card"><div class="ct">👥 Daftar Warga</div>
        <div class="field" style="margin-bottom:8px"><input type="search" id="sw-q" placeholder=" " oninput="filterW(this.value)"><label>Cari nama / No. HP / Grup</label></div>
        <button class="btn btn-ghost btn-sm" onclick="loadWarga()" style="margin-bottom:10px">🔄 Muat Ulang</button>
        <div id="wlist"><div class="loading"><div class="spin"></div></div></div>
      </div>
      <div class="card"><div class="ct">🔓 Reset Perangkat Warga</div>
        <p style="font-size:.8rem;color:var(--tx2);margin-bottom:8px">Gunakan jika warga ganti HP dan tidak bisa login.</p>
        <div class="field"><input type="text" id="reset-hp" placeholder=" " autocapitalize="characters" oninput="this.value=this.value.toUpperCase()"><label>ID Akun / No. HP yang akan direset</label></div>
        <button class="btn btn-wa" onclick="resetDev()">🔓 Reset Perangkat</button>
      </div>
      <div class="card"><div class="ct">🔑 Reset Password Warga</div>
        <p style="font-size:.8rem;color:var(--tx2);margin-bottom:8px">Password lama dinonaktifkan. Warga membuat password baru lewat menu Aktivasi.</p>
        <div class="field"><input type="text" id="reset-pass-id" placeholder=" " autocapitalize="characters" oninput="this.value=this.value.toUpperCase()"><label>ID Akun / No. HP</label></div>
        <button class="btn btn-er" onclick="resetPass()">🔑 Reset Password</button>
      </div>
    </div>

    <div id="aabsen" style="display:none">
      <div class="card"><div class="ct">📝 Isi / Koreksi Absensi Manual</div>
        <div class="field"><select id="ma-warga"><option value="">Pilih warga...</option></select></div>
        <div class="field"><input type="date" id="ma-tgl"><label style="font-size:.65rem;top:7px;transform:none">Tanggal *</label></div>
        <div class="field"><select id="ma-status"><option value="hadir">Hadir</option><option value="izin">Izin</option><option value="sakit">Sakit</option><option value="alpa">Alpa</option><option value="lainnya">Lainnya</option></select></div>
        <div class="field-row">
          <div class="field"><input type="time" id="ma-in"><label style="font-size:.65rem;top:7px;transform:none">Jam Masuk (opsional)</label></div>
          <div class="field"><input type="time" id="ma-out"><label style="font-size:.65rem;top:7px;transform:none">Jam Keluar (opsional)</label></div>
        </div>
        <div class="field"><textarea id="ma-ket" placeholder=" "></textarea><label>Keterangan</label></div>
        <button class="btn btn-ok" onclick="saveManualAttendance()">💾 Simpan Absensi</button>
      </div>
      <div class="card"><div class="ct">📋 Absensi pada Tanggal</div>
        <button class="btn btn-ghost btn-sm" onclick="loadManualAttendance()" style="margin-bottom:10px">🔄 Muat Data</button>
        <div id="manual-att-list"></div>
      </div>
    </div>

    <div id="agrup" style="display:none">
      <div class="card"><div class="ct">🏘️ Kelola Grup Ronda</div>
        <p style="font-size:.8rem;color:var(--tx2);margin-bottom:10px">Atur nama dan deskripsi setiap grup ronda.</p>
        <button class="btn btn-ghost btn-sm" onclick="loadAdminGroups()" style="margin-bottom:10px">🔄 Muat Grup</button>
        <div id="group-list"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>

    <div id="acp" style="display:none">
      <div class="card"><div class="ct">➕ Tambah Checkpoint</div>
        <div class="field"><input type="text" id="nc-nama" placeholder=" "><label>Nama Pos *</label></div>
        <div class="field"><input type="text" id="nc-tok" placeholder=" " style="text-transform:uppercase"><label>Token QR *</label></div>
        <div class="field"><select id="nc-tipe"><option value="patrol">📍 Patroli</option>
          <option value="checkin">✅ Check-IN</option><option value="checkout">🚩 Check-OUT</option></select></div>
        <div class="field"><input type="text" id="nc-lok" placeholder=" "><label>Lokasi / Keterangan</label></div>
        <div class="field-row">
          <div class="field" style="margin:0"><input type="number" id="nc-lat" placeholder=" " step="any"><label>Latitude GPS</label></div>
          <div class="field" style="margin:0"><input type="number" id="nc-lon" placeholder=" " step="any"><label>Longitude GPS</label></div>
        </div>
        <div class="field"><input type="number" id="nc-order" placeholder=" " min="1"><label>Urutan Rute (kosong = terakhir)</label></div>
        <div class="field"><input type="number" id="nc-radius" placeholder=" " min="25" max="1000" value="30"><label>Radius Pos (meter, default 30)</label></div>
        <button class="btn btn-ok" onclick="addCP()">✅ Tambah Checkpoint</button>
      </div>
      <div class="card"><div class="ct">📌 Daftar Checkpoint</div>
        <button class="btn btn-ghost btn-sm" onclick="loadCPAdmin()" style="margin-bottom:10px">🔄 Muat Ulang</button>
        <div id="cplist"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>

    <div id="aset" style="display:none">
      <div class="card"><div class="ct">⚙️ Pengaturan Sistem</div>
        <p style="font-size:.76rem;color:var(--tx2);line-height:1.5;margin-bottom:10px">Retensi foto hanya menghapus salinan foto patroli dari server dan chat. File asli yang dipilih dari galeri perangkat tidak disentuh.</p>
        <button class="btn btn-ghost btn-sm" onclick="loadSettings()" style="margin-bottom:12px">🔄 Muat</button>
        <div id="setlist"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>

    <div id="ajadwal" style="display:none">
      <div class="card"><div class="ct">➕ Tambah Jadwal Ronda</div>
        <div class="field"><input type="number" id="jd-grup" placeholder=" " min="1"><label>Nomor Grup *</label></div>
        <div class="field"><select id="jd-hari">
          <option value="">Pilih Hari Reguler...</option>
          <option value="0">Senin</option><option value="1">Selasa</option>
          <option value="2">Rabu</option><option value="3">Kamis</option>
          <option value="4">Jumat</option><option value="5">Sabtu</option><option value="6">Minggu</option>
        </select></div>
        <p style="text-align:center;font-size:.76rem;color:var(--tx3);margin-bottom:7px">— atau —</p>
        <div class="field"><input type="date" id="jd-tgl">
          <label style="font-size:.65rem;top:7px;transform:none">Tanggal Khusus (Override)</label></div>
        <div class="field"><input type="text" id="jd-cat" placeholder=" "><label>Catatan</label></div>
        <button class="btn btn-ok" onclick="addJadwal()">✅ Tambah Jadwal</button>
      </div>
      <div class="card"><div class="ct">📋 Jadwal Semua Grup</div>
        <button class="btn btn-ghost btn-sm" onclick="loadAllSchedules()" style="margin-bottom:10px">🔄 Muat</button>
        <div id="all-schedules"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>

    <div id="apengganti" style="display:none">
      <div class="card"><div class="ct">🔄 Tambah Pengganti Ronda</div>
        <p style="font-size:.8rem;color:var(--tx2);margin-bottom:10px;line-height:1.5">Warga pengganti dapat Check-IN meski bukan jadwal grupnya.</p>
        <div class="field"><input type="date" id="pg-tgl">
          <label style="font-size:.65rem;top:7px;transform:none">Tanggal</label></div>
        <div class="field"><input type="number" id="pg-grup" placeholder=" " min="1"><label>Nomor Grup yang Digantikan</label></div>
        <div class="field"><select id="pg-asli"><option value="">Pilih Warga Asli (yang digantikan)...</option></select></div>
        <div class="field"><select id="pg-pgti"><option value="">Pilih Warga Pengganti...</option></select></div>
        <div class="field"><input type="text" id="pg-cat" placeholder=" "><label>Catatan</label></div>
        <div style="display:flex;gap:7px;margin-bottom:10px">
          <button class="btn btn-ghost btn-sm" onclick="loadWargaDropdowns()">🔄 Muat Daftar Warga</button>
        </div>
        <button class="btn btn-ok" onclick="addPengganti()">✅ Tambah Pengganti</button>
      </div>
      <div class="card"><div class="ct">📋 Pengganti Aktif</div>
        <button class="btn btn-ghost btn-sm" onclick="loadPengganti()" style="margin-bottom:10px">🔄 Muat</button>
        <div id="pengganti-list"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>

    <div id="akompensasi" style="display:none">
      <div class="sg" id="komp-summary"></div>
      <div class="card"><div class="ct">💳 Laporan Kompensasi Ronda</div>
        <p style="font-size:.8rem;color:var(--tx2);line-height:1.5;margin-bottom:10px">Rincian warga, grup, jadwal, nominal, status pembayaran, dan petugas verifikasi.</p>
        <div class="field-row">
          <div class="field" style="margin:0"><select id="admin-komp-status" onchange="loadKompensasi('admin-komp-list','admin')"><option value="belum">Belum Dibayar</option><option value="lunas">Sudah Lunas</option><option value="dibatalkan">Dibatalkan</option><option value="all">Semua Status</option></select></div>
          <div class="field" style="margin:0"><input type="number" id="admin-komp-grup" min="1" placeholder=" " onchange="loadKompensasi('admin-komp-list','admin')"><label>Filter Grup</label></div>
        </div>
        <div style="display:flex;gap:7px;margin:10px 0;flex-wrap:wrap">
          <button class="btn btn-ghost btn-sm" onclick="loadKompensasi('admin-komp-list','admin')">🔄 Perbarui</button>
          <button class="btn btn-ok btn-sm" onclick="exportKompensasi('admin')">📊 Unduh Laporan Excel</button>
        </div>
        <div id="admin-komp-list"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>

    <div id="adata" style="display:none">
      <div class="card"><div class="ct">⇄ Impor & Ekspor Data</div>
        <p style="font-size:.8rem;color:var(--tx2);line-height:1.55;margin-bottom:10px">Pilih semua data atau hanya bagian tertentu. Ekspor Excel membuat satu sheet per dataset dan satu field per kolom, sehingga dapat langsung dibaca, diedit, lalu diimpor kembali.</p>
        <label class="data-check" style="background:var(--pa);border-color:var(--p);margin-bottom:8px"><input type="checkbox" id="data-all" checked onchange="toggleAllDatasets(this.checked)"><span>Semua data</span></label>
        <div class="data-grid" id="dataset-grid"><div class="loading" style="grid-column:1/-1"><div class="spin"></div></div></div>
        <div class="field-row">
          <button class="btn btn-p" onclick="exportData('json')">{ } Ekspor JSON</button>
          <button class="btn btn-ok" onclick="exportData('xlsx')">📊 Ekspor Excel</button>
        </div>
        <div style="margin-top:8px"><button class="btn btn-ghost" onclick="downloadWargaTemplate()">⬇️ Unduh Template Excel Warga</button></div>
        <p style="font-size:.72rem;color:var(--wa);margin-top:9px;line-height:1.5">🔐 Ekspor lengkap dapat berisi hash password dan identitas perangkat. Simpan file dengan aman.</p>
      </div>
      <div class="card"><div class="ct">📥 Impor ke Database</div>
        <p style="font-size:.8rem;color:var(--tx2);line-height:1.55;margin-bottom:10px">Terima file JSON hasil ekspor atau Excel .xlsx dengan nama field pada baris pertama. Untuk input cepat warga, isi setiap data pada kolom template lalu unggah kembali.</p>
        <div class="field"><input type="file" id="data-import-file" accept=".json,.xlsx,application/json,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" style="padding-top:18px"><label>File JSON / Excel .xlsx</label></div>
        <div class="field"><select id="data-import-mode"><option value="merge">Gabungkan: tambah baru & perbarui yang cocok</option><option value="new">Hanya tambahkan data baru</option></select></div>
        <button class="btn btn-cy" id="btn-import-data" onclick="importData()">📥 Mulai Impor</button>
        <div id="data-import-result" style="display:none" class="import-result"></div>
      </div>
    </div>

    <div id="alap" style="display:none">
      <div class="card"><div class="ct">📥 Ekspor Laporan Excel</div>
        <div class="field-row" style="margin-bottom:12px">
          <div class="field" style="margin:0"><input type="date" id="ex-m">
            <label style="font-size:.65rem;top:7px;transform:none">Dari Tanggal</label></div>
          <div class="field" style="margin:0"><input type="date" id="ex-s">
            <label style="font-size:.65rem;top:7px;transform:none">Sampai</label></div>
        </div>
        <button class="btn btn-ok" onclick="expA()" style="margin-bottom:8px">📊 Unduh Excel Absensi</button>
        <button class="btn btn-cy" onclick="expP()">📸 Unduh Excel Patroli</button>
      </div>
    </div>

    <div id="asos" style="display:none">
      <div class="card"><div class="ct">🆘 Alert Darurat</div>
        <button class="btn btn-ghost btn-sm" onclick="loadSOS()" style="margin-bottom:10px">🔄 Perbarui</button>
        <div id="soslist"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>

    <div id="alog" style="display:none">
      <div class="card"><div class="ct">🔍 Audit Log</div>
        <button class="btn btn-ghost btn-sm" onclick="loadAudit()" style="margin-bottom:10px">🔄 Muat Log</button>
        <div id="auditlist"><div class="loading"><div class="spin"></div></div></div>
      </div>
    </div>
  </div>
</div>

<!-- ══ BOTTOM NAV ══ -->
<nav class="bnav" id="bnav" style="display:none">
  <button class="ni" onclick="goTab('home')" id="tab-home"><div class="ni-pill"></div><span class="ic">🏠</span><span class="lb">Beranda</span></button>
  <button class="ni" onclick="goTab('absen')" id="tab-absen"><div class="ni-pill"></div><span class="ic">📲</span><span class="lb">Absensi</span></button>
  <button class="ni" onclick="goTab('patrol')" id="tab-patrol"><div class="ni-pill"></div><span class="ic">📍</span><span class="lb">Patroli</span></button>
  <button class="ni" onclick="goTab('grup')" id="tab-grup"><div class="ni-pill"></div><span class="ic">👥</span><span class="lb">Grup</span>
    <span class="ni-badge" id="chat-badge" style="display:none">•</span></button>
  <button class="ni" onclick="goTab('admin')" id="tab-admin" style="display:none">
    <div class="ni-pill"></div><span class="ic">👑</span><span class="lb">Admin</span>
    <span class="ni-badge" id="sos-nb" style="display:none">!</span></button>
</nav>

<!-- ══ MODALS ══ -->
<div id="mo-sos" class="mo">
  <div class="mb"><div class="mb-handle"></div>
    <div class="mb-title">🆘 Kirim Sinyal Darurat</div>
    <div style="background:rgba(244,63,94,.08);border:1px solid rgba(244,63,94,.2);border-radius:var(--r2);padding:11px;margin-bottom:12px;font-size:.8rem;color:#9f1239;line-height:1.5">
      ⚠️ Hanya untuk situasi darurat nyata. Sinyal + GPS dikirim ke seluruh Tim Ronda dan Admin.
    </div>
    <div class="field"><textarea id="sos-ket" placeholder=" " rows="3">Butuh bantuan segera!</textarea><label>Keterangan Darurat</label></div>
    <button class="btn btn-er" onclick="sendSOS()" style="margin-bottom:8px">🆘 KIRIM SINYAL DARURAT</button>
    <button class="btn btn-ghost" onclick="closeMo('mo-sos')">Batal</button>
  </div>
</div>

<div id="mo-notif" class="mo">
  <div class="mb"><div class="mb-handle"></div>
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
      <div class="mb-title" style="margin:0">🔔 Notifikasi</div>
      <div style="display:flex;gap:7px">
        <button class="btn btn-xs btn-ghost" onclick="markAllRead()">✓ Tandai Dibaca</button>
        <button class="btn btn-xs btn-er" onclick="deleteAllNotifs()">🗑 Hapus Semua</button>
        <button class="btn-close" onclick="closeMo('mo-notif')">✕</button>
      </div>
    </div>
    <div class="push-panel" id="push-panel">
      <div style="font-size:.8rem;font-weight:800" id="push-title">📲 Web Push</div>
      <div style="font-size:.72rem;color:var(--tx2);margin:3px 0 8px" id="push-desc">Tetap menerima SOS, chat, dan tagihan saat aplikasi ditutup.</div>
      <div style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn btn-xs btn-p" id="btn-push-toggle" onclick="enableWebPush()">Aktifkan Web Push</button><button class="btn btn-xs btn-ghost" id="btn-push-test" style="display:none" onclick="testWebPush()">Kirim Tes</button></div>
    </div>
    <div id="notif-list"><div class="loading"><div class="spin"></div></div></div>
  </div>
</div>

<div id="mo-result" class="mo result-mo">
  <div class="mb"><div class="mb-handle"></div>
    <div class="result-icon" id="result-icon">✅</div>
    <div class="result-title" id="result-title">Berhasil</div>
    <div class="result-msg" id="result-msg"></div>
    <button class="btn btn-p" onclick="closeMo('mo-result')">OK</button>
  </div>
</div>

<div id="mo-ew" class="mo">
  <div class="mb"><div class="mb-handle"></div>
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
      <div class="mb-title" style="margin:0">✏️ Edit Warga</div>
      <button class="btn-close" onclick="closeMo('mo-ew')">✕</button>
    </div>
    <input type="hidden" id="ew-id">
    <div class="field"><input type="text" id="ew-nama" placeholder=" "><label>Nama Lengkap</label></div>
    <div class="field"><input type="text" id="ew-aid" placeholder=" " maxlength="7" autocapitalize="characters" oninput="this.value=this.value.toUpperCase()"><label>ID Akun (WG/KR/AD/SA + 5 digit)</label></div>
    <div class="field"><input type="tel" id="ew-hp" placeholder=" " inputmode="numeric"><label>No. Handphone</label></div>
    <div class="date-wrap">
      <div class="field"><input type="text" id="ew-lahir" placeholder=" " inputmode="numeric" maxlength="10" oninput="fmtDate(this)" style="padding-right:46px"><label>Tanggal Lahir (DD-MM-YYYY)</label></div>
      <input type="date" id="ew-datepick" onchange="applyDate(this.value,'ew-lahir')">
      <button class="cal-btn" type="button" onclick="openCal('ew-datepick','ew-lahir')">📅</button>
    </div>
    <div class="field-row">
      <div class="field" style="margin:0"><input type="number" id="ew-grup" placeholder=" "><label>Grup</label></div>
      <div class="field" style="margin:0"><select id="ew-role"><option value="warga">Warga</option>
        <option value="koordinator">Koordinator</option><option value="admin">Admin</option></select></div>
    </div>
    <div class="field"><input type="text" id="ew-cat" placeholder=" "><label>Catatan</label></div>
    <label style="display:flex;align-items:center;gap:10px;font-size:.86rem;margin-bottom:14px;cursor:pointer;padding:11px;background:var(--bg);border-radius:var(--r2)">
      <input type="checkbox" id="ew-act" style="width:18px;height:18px;accent-color:var(--p)">
      <span>Akun Aktif</span>
    </label>
    <button class="btn btn-p" onclick="saveEW()">💾 Simpan Perubahan</button>
  </div>
</div>

<div id="mo-group-edit" class="mo">
  <div class="mb"><div class="mb-handle"></div>
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
      <div class="mb-title" style="margin:0">✏️ Edit Grup</div>
      <button class="btn-close" onclick="closeMo('mo-group-edit')">✕</button>
    </div>
    <input type="hidden" id="eg-id">
    <div style="font-size:.8rem;color:var(--tx2);margin-bottom:10px">ID Grup: <b id="eg-num"></b></div>
    <div class="field"><input type="text" id="eg-nama" placeholder=" "><label>Nama Grup *</label></div>
    <div class="field"><input type="text" id="eg-desk" placeholder=" "><label>Deskripsi</label></div>
    <button class="btn btn-p" onclick="saveGroup()">💾 Simpan</button>
  </div>
</div>

<div id="mo-schedule-edit" class="mo">
  <div class="mb"><div class="mb-handle"></div>
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
      <div class="mb-title" style="margin:0">✏️ Edit Jadwal</div><button class="btn-close" onclick="closeMo('mo-schedule-edit')">✕</button>
    </div>
    <input type="hidden" id="ej-id">
    <div class="field"><input type="number" id="ej-grup" placeholder=" " min="1"><label>Nomor Grup</label></div>
    <div class="field"><select id="ej-hari"><option value="">Tanggal Khusus</option><option value="0">Senin</option><option value="1">Selasa</option><option value="2">Rabu</option><option value="3">Kamis</option><option value="4">Jumat</option><option value="5">Sabtu</option><option value="6">Minggu</option></select></div>
    <div class="field"><input type="date" id="ej-tgl"><label style="font-size:.65rem;top:7px;transform:none">Tanggal Khusus</label></div>
    <div class="field"><input type="text" id="ej-cat" placeholder=" "><label>Catatan</label></div>
    <button class="btn btn-p" onclick="saveEditJadwal()">💾 Simpan Perubahan</button>
  </div>
</div>
<script>
// ── STATE ─────────────────────────────────────────────────
const S={
  token:localStorage.getItem("sk_t"),uid:localStorage.getItem("sk_u"),
  nama:localStorage.getItem("sk_n"),role:localStorage.getItem("sk_r")||"warga",
  grup:localStorage.getItem("sk_g")||"1",
  inst:localStorage.getItem("sk_i")||(()=>{const id=Math.random().toString(36).slice(2)+Date.now().toString(36);localStorage.setItem("sk_i",id);return id;})(),
  registered:localStorage.getItem("sk_reg")==="1"
};
let activeTab="home",patrolGPS=null,patrolSelectedCP=null,patrolRoute=null,patrolPoll=null,chatPoll=null,notifPoll=null,loginSetup=false,apiPending=0;
let lastNotifTime=null,lastChatTime=null,scanners={},allWarga=[],currentChatRoom=localStorage.getItem("sk_chat_room")||"0";
let replyTarget=null; // {id, pesan, nama}
let pendingPushTarget=new URLSearchParams(location.search).get("push");

// ── SOUND ─────────────────────────────────────────────────
const Snd=(()=>{
  let ctx=null;
  const init=()=>{if(!ctx)ctx=new(window.AudioContext||window.webkitAudioContext)();if(ctx.state==="suspended")ctx.resume();return ctx;};
  const tone=(f,d,t="sine",v=0.28)=>{try{const c=init(),o=c.createOscillator(),g=c.createGain();o.type=t;o.frequency.value=f;g.gain.setValueAtTime(v,c.currentTime);g.gain.exponentialRampToValueAtTime(.001,c.currentTime+d);o.connect(g);g.connect(c.destination);o.start();o.stop(c.currentTime+d);}catch(e){}};
  return{
    checkin(){tone(523,.1);setTimeout(()=>tone(659,.1),100);setTimeout(()=>tone(784,.22),210);},
    checkout(){tone(784,.1);setTimeout(()=>tone(659,.1),100);setTimeout(()=>tone(523,.22),210);},
    patrol(){tone(440,.07);setTimeout(()=>tone(550,.14),100);},
    chat(){tone(1047,.05,"triangle",.1);},
    notif(){tone(880,.08,"sine",.16);setTimeout(()=>tone(1108,.18,"sine",.1),85);},
    invite(){tone(659,.09);setTimeout(()=>tone(784,.09),110);setTimeout(()=>tone(1047,.25),230);},
    sos(){for(let i=0;i<6;i++){setTimeout(()=>tone(1320,.11,"square",.7),i*240);setTimeout(()=>tone(880,.11,"square",.7),i*240+125);}}
  };
})();

// ── PHOTO COMPRESS ────────────────────────────────────────
async function compressImage(file,maxKB=400,maxDim=1080){
  return new Promise((res,rej)=>{
    const reader=new FileReader();
    reader.onload=e=>{
      const img=new Image();
      img.onload=()=>{
        let{width:w,height:h}=img;
        if(w>maxDim||h>maxDim){if(w>h){h=h/w*maxDim;w=maxDim;}else{w=w/h*maxDim;h=maxDim;}}
        const c=document.createElement("canvas");c.width=Math.round(w);c.height=Math.round(h);
        const ctx=c.getContext("2d");ctx.fillStyle="#fff";ctx.fillRect(0,0,c.width,c.height);ctx.drawImage(img,0,0,c.width,c.height);
        c.toBlob(blob=>blob?res(new File([blob],"photo.jpg",{type:"image/jpeg",lastModified:Date.now()})):rej(new Error("Kompresi foto gagal")),"image/jpeg",.78);
      };img.onerror=()=>rej(new Error("Foto tidak dapat dibaca"));img.src=e.target.result;
    };reader.onerror=()=>rej(new Error("Foto tidak dapat dibaca"));reader.readAsDataURL(file);
  });
}

// ── CONFIRM MODAL ─────────────────────────────────────────
function showConfirm(title,msg,onYes,btnLabel="Ya, Lanjutkan",danger=false){
  const id="cf"+Date.now(),el=document.createElement("div");
  el.className="mo open";el.id=id;
  el.innerHTML=`<div class="mb"><div class="mb-handle"></div>
    <div class="mb-title">${title}</div>
    <p style="color:var(--tx2);margin-bottom:20px;line-height:1.6">${msg}</p>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
      <button class="btn btn-ghost" id="${id}n">Batal</button>
      <button class="btn ${danger?"btn-er":"btn-p"}" id="${id}y">${btnLabel}</button>
    </div></div>`;
  document.body.appendChild(el);
  const rm=()=>{if(el.parentNode)document.body.removeChild(el);};
  el.querySelector(`#${id}y`).onclick=()=>{rm();onYes();};
  el.querySelector(`#${id}n`).onclick=rm;
  el.addEventListener("click",e=>{if(e.target===el)rm();});
}

// ── RESULT MODAL ──────────────────────────────────────────
function showResult(icon,title,msg,type="ok"){
  document.getElementById("result-icon").textContent=icon;
  document.getElementById("result-title").textContent=title;
  document.getElementById("result-title").style.color=type==="ok"?"var(--ok)":type==="er"?"var(--er)":"var(--wa)";
  document.getElementById("result-msg").textContent=msg;
  openMo("mo-result");
}

// ── API HELPER ────────────────────────────────────────────
async function api(m,p,b){
  apiPending++;document.getElementById("app-progress")?.classList.add("show");
  const o={method:m,headers:{}};
  if(S.token)o.headers["Authorization"]="Bearer "+S.token;
  if(b)o.body=b;
  try{
    const r=await fetch(p,o);
    const d=await r.json().catch(()=>({}));
    if(!r.ok)throw new Error(d.detail||`Error ${r.status}`);
    return d;
  }finally{
    apiPending=Math.max(0,apiPending-1);if(!apiPending)setTimeout(()=>document.getElementById("app-progress")?.classList.remove("show"),120);
  }
}
function fd(...a){const f=new FormData();for(let i=0;i<a.length;i+=2)if(a[i+1]!==null&&a[i+1]!==undefined&&a[i+1]!=="")f.append(a[i],a[i+1]);return f;}

// ── TOAST ─────────────────────────────────────────────────
function toast(msg,err=false,ms=3000){
  const el=document.getElementById("toast");
  el.style.background=err?"linear-gradient(135deg,#dc2626,#ef4444)":"linear-gradient(135deg,#059669,#10b981)";
  el.textContent=msg;el.classList.remove("show");void el.offsetWidth;el.classList.add("show");
  clearTimeout(el._t);el._t=setTimeout(()=>{el.classList.remove("show");},ms);
}

// ── DARK MODE ─────────────────────────────────────────────
function toggleDark(){
  const d=document.documentElement.getAttribute("data-theme")==="dark";
  const n=d?"light":"dark";document.documentElement.setAttribute("data-theme",n);
  document.getElementById("btn-dark").textContent=n==="dark"?"☀️":"🌙";
  document.getElementById("tc").content=n==="dark"?"#1e293b":"#6366f1";
  localStorage.setItem("sk_dk",n);
}
if(localStorage.getItem("sk_dk")==="dark"){document.documentElement.setAttribute("data-theme","dark");document.getElementById("btn-dark").textContent="☀️";}

// ── DATE HELPERS ──────────────────────────────────────────
function fmtDate(el){let v=el.value.replace(/\D/g,"");if(v.length>2)v=v.slice(0,2)+"-"+v.slice(2);if(v.length>5)v=v.slice(0,5)+"-"+v.slice(5,9);el.value=v;}
function openCal(pickId,targetId){
  const dp=document.getElementById(pickId),cur=document.getElementById(targetId).value;
  if(cur&&cur.length===10){const[d,m,y]=cur.split("-");if(d&&m&&y)dp.value=`${y}-${m}-${d}`;}
  dp.showPicker?dp.showPicker():dp.click();
}
function applyDate(iso,targetId){if(!iso)return;const[y,m,d]=iso.split("-");document.getElementById(targetId).value=`${d}-${m}-${y}`;}

// ── MODAL ─────────────────────────────────────────────────
function openMo(id){document.getElementById(id).classList.add("open");}
function closeMo(id){document.getElementById(id).classList.remove("open");}
document.querySelectorAll(".mo").forEach(mo=>mo.addEventListener("click",e=>{if(e.target===mo)mo.classList.remove("open");}));

// ── AVATAR HELPER ─────────────────────────────────────────
function avatar(nama,foto,sz=36){
  const ini=nama?nama.charAt(0).toUpperCase():"?";
  if(foto)return`<div style="width:${sz}px;height:${sz}px;border-radius:50%;overflow:hidden;flex-shrink:0;background:var(--bg3)"><img src="/uploads/profile/${foto}" alt="Foto profil ${nama||"warga"}" style="width:100%;height:100%;object-fit:cover;display:block" onerror="this.parentNode.textContent='${ini}';this.parentNode.style.cssText+='display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,var(--pd),var(--pl));color:#fff;font-weight:800'" ></div>`;
  return`<div style="width:${sz}px;height:${sz}px;border-radius:50%;background:linear-gradient(135deg,var(--pd),var(--pl));display:flex;align-items:center;justify-content:center;color:#fff;font-weight:800;font-size:${Math.round(sz*.38)}px;flex-shrink:0">${ini}</div>`;
}

// ── NAV ───────────────────────────────────────────────────
function goTab(name){
  document.querySelectorAll(".view").forEach(v=>{if(v.id!=="view-login")v.classList.remove("active");});
  document.querySelectorAll(".ni").forEach(n=>n.classList.remove("active"));
  const v=document.getElementById("view-"+name);
  if(v){v.classList.remove("active");void v.offsetWidth;v.classList.add("active");}
  const t=document.getElementById("tab-"+name);if(t)t.classList.add("active");
  stopScanners();activeTab=name;
  if(name==="home"){loadStats();loadAbsenStatus("home");loadJadwalHome();loadMyKompensasi();}
  if(name==="absen"){loadCPList();loadAbsenStatus("inline");}
  if(name==="patrol"){loadCPPatrol();loadPatrolRoute();if(patrolPoll)clearInterval(patrolPoll);patrolPoll=setInterval(loadPatrolRoute,10000);}
  if(name==="grup"){loadMembers();loadGrupInfo();loadChatRooms();startChatPoll();loadChatInvites();loadGrupJadwal();}
  if(name==="admin")loadAdminStats();
  if(name!=="grup")stopChatPoll();
  if(name!=="patrol"&&patrolPoll){clearInterval(patrolPoll);patrolPoll=null;}
}

// ── QR SCANNER ────────────────────────────────────────────
async function toggleQR(ctx){
  const rdiv=document.getElementById("qr-reader-"+ctx),btn=document.getElementById("btn-scan-"+ctx);
  if(scanners[ctx]){await scanners[ctx].stop().catch(()=>{});scanners[ctx].clear();delete scanners[ctx];rdiv.style.display="none";rdiv.innerHTML="";btn.innerHTML="📷 Buka Kamera QR Scanner";return;}
  rdiv.style.display="block";rdiv.innerHTML="";btn.innerHTML="⏹ Tutup Scanner";
  const scanner=new Html5Qrcode("qr-reader-"+ctx);scanners[ctx]=scanner;
  try{
    await scanner.start({facingMode:"environment"},{fps:10,qrbox:{width:200,height:200}},
      code=>{
        const c=code.trim().toUpperCase();document.getElementById("inp-qr-"+ctx).value=c;
        const rb=document.getElementById("qrr-"+ctx);rb.textContent="✅ Token: "+c;rb.style.display="block";
        scanner.stop().catch(()=>{});delete scanners[ctx];rdiv.style.display="none";rdiv.innerHTML="";
        btn.innerHTML="📷 Buka Kamera QR Scanner";Snd.notif();
      },()=>{}
    );
  }catch(e){toast("Kamera gagal: "+e,true);rdiv.style.display="none";btn.innerHTML="📷 Buka Kamera QR Scanner";delete scanners[ctx];}
}
function stopScanners(){Object.keys(scanners).forEach(async ctx=>{try{await scanners[ctx].stop();scanners[ctx].clear();}catch(e){}delete scanners[ctx];const r=document.getElementById("qr-reader-"+ctx);if(r){r.style.display="none";r.innerHTML="";}});}

// ── INIT ──────────────────────────────────────────────────
async function init(){
  document.body.classList.remove("authenticated");
  try{
    const pub=await api("GET","/api/settings/public");
    const kn=pub.nama_kampung||"Siskamling Digital";
    document.getElementById("lkn").textContent=kn;
    document.getElementById("app-title").textContent=kn;
    document.title=kn;
    const jam=`Aktif: ${pub.jam_mulai||"23:00"} – ${pub.jam_selesai||"04:00"} WIB`;
    const ji=document.getElementById("jam-info");if(ji)ji.textContent=jam;
  }catch(e){}
  updateLoginUI();
  if(S.token){
    try{
      const me=await api("GET","/api/me");
      S.nama=me.nama;localStorage.setItem("sk_n",me.nama);
      S.role=me.role;localStorage.setItem("sk_r",me.role);
      S.grup=me.grup_id;localStorage.setItem("sk_g",me.grup_id);
      startApp();return;
    }catch(e){localStorage.removeItem("sk_t");localStorage.removeItem("sk_u");S.token=null;}
  }
  document.getElementById("view-login").classList.add("active");
}

function updateLoginUI(){
  const ph=document.getElementById("photo-section"),badge=document.getElementById("login-badge");
  if(ph)ph.style.display=!S.registered?"":"none";
  if(badge)badge.textContent=loginSetup?(S.registered?"🔑 Buat Password Baru":"✨ Aktivasi Perangkat Baru"):(S.registered?"✅ Perangkat Terdaftar":"🔐 Login Aman");
}

function setLoginMode(setup){
  loginSetup=setup;
  document.getElementById("activation-fields").style.display=setup?"block":"none";
  document.getElementById("login-password-row").style.display=setup?"none":"block";
  document.getElementById("login-mode-btn").classList.toggle("active",!setup);
  document.getElementById("setup-mode-btn").classList.toggle("active",setup);
  document.getElementById("login-help").innerHTML=setup?"Verifikasi <b>ID akun/No. HP + tanggal lahir</b>, lalu buat password baru.":"Masukkan <b>ID akun seperti WG00001 atau No. HP</b> dan password.";
  document.getElementById("btn-login").innerHTML=setup?"✨ Aktivasi &amp; Masuk":"🔐 Masuk";
  updateLoginUI();
}

function startApp(){
  document.body.classList.add("authenticated");
  const lv=document.getElementById("view-login");
  lv.style.animation="fadeOut .25s ease forwards";
  setTimeout(()=>{ lv.classList.remove("active"); lv.style.display="none"; },280);
  document.getElementById("bnav").style.display="flex";
  document.getElementById("btn-logout").style.display="flex";
  document.getElementById("btn-notif").style.display="flex";
  document.getElementById("greet").textContent=`Halo, ${(S.nama||"").split(" ")[0]}! 👋`;
  document.getElementById("rbadge").textContent=(S.role||"warga").toUpperCase();
  if(["admin","super_admin"].includes(S.role))document.getElementById("tab-admin").style.display="flex";
  const inviteCard=document.getElementById("invite-manager-card");
  if(inviteCard)inviteCard.style.display=["koordinator","admin","super_admin"].includes(S.role)?"block":"none";
  const kompTab=document.getElementById("gtab-kompensasi");
  if(kompTab)kompTab.style.display=["koordinator","admin","super_admin"].includes(S.role)?"block":"none";
  startNotifPoll();goTab("home");syncPushState(true);
  if(pendingPushTarget)setTimeout(()=>handlePushTarget(pendingPushTarget),450);
}
document.head.insertAdjacentHTML("beforeend",`<style>@keyframes fadeOut{to{opacity:0;transform:translateY(-8px)}}</style>`);

async function prevPhoto(inp){
  if(!inp.files[0])return;
  const file=await compressImage(inp.files[0]);
  const dt=new DataTransfer();dt.items.add(file);inp.files=dt.files;
  const r=new FileReader();r.onload=e=>{
    const img=document.getElementById("photo-prev");
    img.src=e.target.result;img.style.display="block";
    document.getElementById("photo-ph").style.display="none";
    document.getElementById("photo-box").classList.add("has");
  };r.readAsDataURL(file);
}

async function doLogin(){
  const identifier=document.getElementById("inp-identifier").value.trim();
  const password=document.getElementById("inp-password").value;
  const lahir=document.getElementById("inp-lahir").value.trim();
  const newPassword=document.getElementById("inp-new-password").value;
  const confirmPassword=document.getElementById("inp-confirm-password").value;
  const filo=document.getElementById("inp-foto"),foto=filo.files[0];
  if(!identifier){toast("Isi ID warga atau No. HP",true);return;}
  if(!loginSetup&&!password){toast("Isi password",true);return;}
  if(loginSetup&&lahir.length<10){toast("Isi tanggal lahir dengan format DD-MM-YYYY",true);return;}
  if(loginSetup&&(newPassword.length<6||!/[A-Za-z]/.test(newPassword)||!/\d/.test(newPassword))){toast("Password minimal 6 karakter dan wajib mengandung huruf serta angka",true);return;}
  if(loginSetup&&newPassword!==confirmPassword){toast("Konfirmasi password tidak sama",true);return;}
  if(!S.registered&&!foto){toast("Upload selfie untuk perangkat baru",true);return;}
  const btn=document.getElementById("btn-login");btn.disabled=true;btn.textContent="⏳ Memverifikasi...";
  try{
    const f=fd("identifier",identifier,"password",loginSetup?"":password,"tgl_lahir",loginSetup?lahir:"","new_password",loginSetup?newPassword:"","installation_id",S.inst);
    if(foto){const comp=await compressImage(foto);f.append("foto_profil",comp);}
    const d=await api("POST","/api/auth/activate",f);
    S.token=d.token;localStorage.setItem("sk_t",d.token);
    S.uid=d.warga_id;localStorage.setItem("sk_u",d.warga_id);
    S.nama=d.nama;localStorage.setItem("sk_n",d.nama);
    S.role=d.role;localStorage.setItem("sk_r",d.role);
    S.grup=d.grup_id;localStorage.setItem("sk_g",d.grup_id);
    S.registered=true;localStorage.setItem("sk_reg","1");
    toast("✅ Masuk berhasil! Selamat, "+d.nama.split(" ")[0]+"!");Snd.notif();
    setTimeout(startApp,500);
  }catch(e){
    toast(e.message,true,5000);
    if(e.message.includes("Tanggal lahir")||e.message.includes("Password minimal")){setLoginMode(true);}
    if(e.message.includes("foto")||e.message.includes("wajib")){S.registered=false;localStorage.removeItem("sk_reg");updateLoginUI();}
  }
  btn.disabled=false;btn.innerHTML=loginSetup?"✨ Aktivasi &amp; Masuk":"🔐 Masuk";
}

function confirmLogout(){
  showConfirm("Keluar Aplikasi","Anda yakin ingin keluar? Sesi dan Web Push pada perangkat ini akan dihapus.",async()=>{
    try{await disableWebPush(true);}catch(e){}
    ["sk_t","sk_u","sk_n","sk_r","sk_g"].forEach(k=>localStorage.removeItem(k));location.reload();
  },"Ya, Keluar",true);
}

// ── GPS ───────────────────────────────────────────────────
function getGPS(timeout=10000){
  return new Promise((res,rej)=>{
    if(!navigator.geolocation){rej("GPS tidak didukung.");return;}
    navigator.geolocation.getCurrentPosition(
      p=>res({lat:p.coords.latitude,lon:p.coords.longitude,acc:p.coords.accuracy}),
      ()=>rej("GPS gagal. Berikan izin lokasi di browser."),
      {enableHighAccuracy:true,timeout}
    );
  });
}
function haversine(lat1,lon1,lat2,lon2){
  const R=6371000,dl=(lat2-lat1)*Math.PI/180,dlo=(lon2-lon1)*Math.PI/180;
  const a=Math.sin(dl/2)**2+Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dlo/2)**2;
  return R*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a));
}

// ── STATS ─────────────────────────────────────────────────
function animNum(el,to,dur=600){
  const start=performance.now();
  const fn=now=>{const t=Math.min((now-start)/dur,1),ease=1-Math.pow(1-t,3);el.textContent=Math.round(to*ease);if(t<1)requestAnimationFrame(fn);};
  requestAnimationFrame(fn);
}
async function loadStats(){
  try{
    const d=await api("GET","/api/stats");
    animNum(document.getElementById("sw"),d.total_warga);animNum(document.getElementById("sa"),d.absen_hari_ini);
    animNum(document.getElementById("sp"),d.patroli_hari_ini);animNum(document.getElementById("se"),d.emergency_aktif);
    const b=document.getElementById("sos-nb");if(b)b.style.display=d.emergency_aktif>0?"block":"none";
  }catch(e){}
}
async function loadJadwalHome(){
  const box=document.getElementById("jadwal-home");if(!box)return;
  try{
    const d=await api("GET","/api/group/schedule");
    const HARI=["Senin","Selasa","Rabu","Kamis","Jumat","Sabtu","Minggu"];
    const today=HARI[new Date().getDay()===0?6:new Date().getDay()-1];
    const todayStr=new Date().toISOString().slice(0,10);
    const aktif=d.find(j=>j.hari_nama===today||j.tanggal===todayStr);
    box.innerHTML=`<div class="card"><div class="ct">📅 Jadwal Grup</div>
      ${aktif?`<span class="jadwal-chip active">✅ Berjadwal Hari Ini (${today})</span>`:`<span class="jadwal-chip inactive">❌ Tidak Berjadwal Hari Ini (${today})</span>`}
      <div style="font-size:.78rem;color:var(--tx2);margin-top:7px">${d.length?d.map(j=>`<span class="badge" style="margin:2px">${j.hari_nama}</span>`).join(""):"Belum ada jadwal"}</div>
    </div>`;
  }catch(e){if(box)box.innerHTML="";}
}

function rupiah(value){return new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(Number(value)||0);}
async function loadMyKompensasi(){
  const box=document.getElementById("kompensasi-home");if(!box)return;
  try{
    const d=await api("GET","/api/compensations/me");
    if(!d.count){box.innerHTML="";return;}
    box.innerHTML=`<div class="komp-alert"><div style="display:flex;justify-content:space-between;gap:10px;align-items:flex-start"><div><b>💳 Tagihan Kompensasi Ronda</b><div style="font-size:.78rem;color:var(--tx2);margin-top:3px">${d.count} tagihan belum terverifikasi</div></div><b style="color:#b45309;white-space:nowrap">${rupiah(d.total)}</b></div><div style="margin-top:9px">${d.items.map(k=>`<div style="font-size:.78rem;padding:7px 0;border-top:1px dashed rgba(180,83,9,.25)"><b>${k.hari}, ${k.tanggal}</b> · Grup ${k.grup_id}<br><span style="color:var(--tx2)">${k.alasan} · ${rupiah(k.nominal)}</span></div>`).join("")}</div><p style="font-size:.72rem;color:var(--tx2);margin-top:7px">Hubungi Koordinator atau Admin setelah pembayaran agar tagihan diverifikasi dan dihapus dari beranda.</p></div>`;
  }catch(e){box.innerHTML="";}
}

async function loadKompensasi(targetId,scope){
  const box=document.getElementById(targetId);if(!box)return;box.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  const status=document.getElementById(scope==="admin"?"admin-komp-status":"group-komp-status")?.value||"belum";
  const group=scope==="admin"?document.getElementById("admin-komp-grup")?.value:"";
  try{
    const params=new URLSearchParams({status});if(group)params.set("grup_id",group);
    const d=await api("GET",`/api/management/compensations?${params}`),s=d.summary;
    if(scope==="admin"){
      const sg=document.getElementById("komp-summary");sg.innerHTML=[["⏳",s.belum,"Belum Lunas"],["✅",s.lunas,"Sudah Lunas"],["💰",rupiah(s.nominal_belum),"Nilai Belum Lunas"],["📥",rupiah(s.nominal_lunas),"Sudah Masuk"]].map(([i,v,l])=>`<div class="sc"><div>${i}</div><div class="sn" style="font-size:1.15rem;margin-top:5px">${v}</div><div class="sl">${l}</div></div>`).join("");
    }
    if(!d.items.length){box.innerHTML=`<p style="color:var(--tx2);text-align:center;padding:18px">Tidak ada data kompensasi pada filter ini.</p>`;return;}
    box.innerHTML=d.items.map(k=>{
      const managerActions=k.status==="belum"?`<button class="btn btn-xs btn-ok" onclick="verifyKompensasi(${k.id},'paid','${targetId}','${scope}')">✅ Verifikasi Bayar</button>${["admin","super_admin"].includes(S.role)?`<button class="btn btn-xs btn-ghost" onclick="verifyKompensasi(${k.id},'cancel','${targetId}','${scope}')">Batalkan</button>`:""}`:"";
      const deleteAction=["admin","super_admin"].includes(S.role)?`<button class="btn btn-xs btn-er" onclick="deleteKompensasi(${k.id},'${targetId}','${scope}')">🗑 Hapus Tagihan</button>`:"";
      return `<div class="komp-row" style="border-left-color:${k.status==="lunas"?"var(--ok)":k.status==="dibatalkan"?"var(--tx3)":"var(--wa)"}"><div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px"><div style="min-width:0"><b>${k.nama}</b> <span class="badge">${k.akun_id||"-"}</span><div style="font-size:.75rem;color:var(--tx2);margin-top:3px">Grup ${k.grup_id} · ${k.hari}, ${k.tanggal} · ${k.no_hp}</div><div style="font-size:.78rem;margin-top:4px">${k.alasan||"Tidak melaksanakan jadwal ronda"}</div><div style="font-size:.72rem;color:var(--tx3);margin-top:3px">${k.verified_by?`Diverifikasi ${k.verified_by} · ${k.verified_at||""}`:`Dibuat ${k.created_at||"-"}`}${k.catatan?`<br>Catatan: ${k.catatan}`:""}</div></div><div style="text-align:right;flex-shrink:0"><b>${rupiah(k.nominal)}</b><br><span class="badge ${k.status==="lunas"?"badge-ok":k.status==="belum"?"badge-wa":""}">${k.status}</span></div></div>${managerActions||deleteAction?`<div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:9px">${managerActions}${deleteAction}</div>`:""}</div>`;
    }).join("");
  }catch(e){box.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
function verifyKompensasi(id,action,targetId,scope){
  const paid=action==="paid",note=paid?"Pastikan pembayaran benar-benar sudah diterima.":"Tagihan akan dibatalkan tanpa dicatat sebagai pembayaran.";
  showConfirm(paid?"Verifikasi Pembayaran":"Batalkan Tagihan",note,async()=>{try{const d=await api("POST",`/api/management/compensations/${id}/verify`,fd("action",action));toast("✅ "+d.message);Snd.notif();loadKompensasi(targetId,scope);loadMyKompensasi();pollNotifs();}catch(e){toast(e.message,true);}},paid?"Ya, Sudah Dibayar":"Ya, Batalkan",!paid);
}
function deleteKompensasi(id,targetId,scope){
  const reason=prompt("Alasan penghapusan tagihan:","Tagihan salah");if(reason===null)return;
  showConfirm("Hapus Tagihan", "Tagihan akan hilang dari akun warga dan tidak dibuat ulang untuk tanggal tersebut. Riwayat audit admin tetap disimpan.",async()=>{
    try{const d=await api("DELETE",`/api/admin/compensations/${id}`,fd("alasan",reason||"Tagihan salah"));toast("🗑 "+d.message);loadKompensasi(targetId,scope);loadMyKompensasi();pollNotifs();}
    catch(e){toast(e.message,true);}
  },"Ya, Hapus Tagihan",true);
}
function exportKompensasi(scope){const status=document.getElementById(scope==="admin"?"admin-komp-status":"group-komp-status")?.value||"all",group=scope==="admin"?document.getElementById("admin-komp-grup")?.value:"";let url=`/api/management/compensations/export?status=${encodeURIComponent(status)}`;if(group)url+=`&grup_id=${encodeURIComponent(group)}`;dlToken(url,`laporan_kompensasi_${new Date().toISOString().slice(0,10)}.xlsx`);}

// ── ABSENSI ───────────────────────────────────────────────
async function loadAbsenStatus(ctx){
  const box=document.getElementById(ctx==="home"?"absen-home":"absen-inline");if(!box)return;
  try{
    const d=await api("GET","/api/attendance/today");
    let h="";
    if(d.status==="belum_absen")h=`<div class="chip chip-n">⭕ Belum Absen Hari Ini</div>`;
    else if(d.status==="manual")h=`<div class="chip chip-wa">📝 ${String(d.status_absen||"manual").toUpperCase()}${d.keterangan?` — ${d.keterangan}`:""}</div>`;
    else if(d.status==="sudah_checkin")h=`<div class="chip chip-wa">✅ Check-IN ${d.check_in} — Belum Check-OUT</div>`;
    else h=`<div class="chip chip-ok">✔ Selesai Ronda ${d.check_in}→${d.check_out} (${d.durasi} menit)</div>`;
    box.innerHTML=h;
  }catch(e){box.innerHTML="";}
}

function parseAbsenError(msg){
  if(msg.startsWith("DILUAR_WAKTU|"))return{icon:"⏰",title:"Di Luar Jam Ronda",body:msg.slice(13)};
  if(msg.startsWith("DILUAR_JADWAL|"))return{icon:"📅",title:"Di Luar Jadwal Grup",body:msg.slice(14)};
  if(msg.startsWith("QR_INVALID|"))return{icon:"❌",title:"Token QR Tidak Valid",body:msg.slice(11)};
  if(msg.startsWith("SUDAH_CHECKIN|"))return{icon:"⚠️",title:"Sudah Check-IN",body:msg.slice(14)};
  if(msg.startsWith("BELUM_CHECKIN|"))return{icon:"⚠️",title:"Belum Check-IN",body:msg.slice(14)};
  return{icon:"❌",title:"Gagal",body:msg};
}

async function doCheckin(){
  const tok=document.getElementById("inp-qr-absen").value.trim();
  if(!tok){toast("Scan atau ketik token QR Check-IN",true);return;}
  try{
    toast("📍 Membaca GPS...",false,8000);const g=await getGPS();
    const d=await api("POST","/api/attendance/checkin",fd("qr_token",tok,"lat",g.lat,"lon",g.lon));
    Snd.checkin();document.getElementById("inp-qr-absen").value="";
    showResult("✅","Check-IN Berhasil!",`Lokasi: ${d.cp_nama}\nWaktu: ${d.waktu||""}`)
    loadAbsenStatus("home");loadAbsenStatus("inline");
  }catch(e){const{icon,title,body}=parseAbsenError(e.message);showResult(icon,title,body,"er");}
}
async function doCheckout(){
  const tok=document.getElementById("inp-qr-absen").value.trim();
  if(!tok){toast("Scan atau ketik token QR Check-OUT",true);return;}
  try{
    toast("📍 Membaca GPS...",false,8000);const g=await getGPS();
    const d=await api("POST","/api/attendance/checkout",fd("qr_token",tok,"lat",g.lat,"lon",g.lon));
    Snd.checkout();document.getElementById("inp-qr-absen").value="";
    showResult("🚩","Check-OUT Berhasil!",`Durasi Ronda: ${d.durasi} menit\nWaktu: ${d.waktu||""}`)
    loadAbsenStatus("home");loadAbsenStatus("inline");
  }catch(e){const{icon,title,body}=parseAbsenError(e.message);showResult(icon,title,body,"er");}
}
async function loadCPList(){
  const box=document.getElementById("cp-absen");
  try{
    const cps=await api("GET","/api/checkpoints");
    const list=cps.filter(c=>c.tipe==="checkin"||c.tipe==="checkout");
    if(!list.length){box.innerHTML=`<p style="color:var(--tx2);font-size:.83rem">Belum ada pos absensi.</p>`;return;}
    // Token hanya tampil jika ada (koordinator/admin) — warga tidak
    box.innerHTML=list.map(c=>`<div class="cp-row">
      <div><b style="font-size:.86rem">${c.nama}</b><div style="font-size:.73rem;color:var(--tx2)">${c.lokasi||""}</div></div>
      <div style="display:flex;gap:5px;align-items:center">
        ${c.token?`<span class="badge ${c.tipe==="checkin"?"badge-ok":"badge-er"}">${c.token}</span>
        <button class="btn btn-xs btn-ghost" onclick="document.getElementById('inp-qr-absen').value='${c.token}'">Pakai</button>`
        :`<span class="badge">${c.tipe==="checkin"?"Check-IN":"Check-OUT"}</span>`}
      </div></div>`).join("");
  }catch(e){box.innerHTML="";}
}

// ── PATROLI GPS ───────────────────────────────────────────
async function loadPatrolRoute(){
  const box=document.getElementById("patrol-route");if(!box)return;
  try{
    const d=await api("GET","/api/patrol/route");patrolRoute=d;
    if(!d.total){box.innerHTML=`<p style="font-size:.8rem;color:var(--wa);margin-top:10px">Belum ada checkpoint patroli aktif. Admin perlu menambahkan dan mengurutkan checkpoint.</p>`;return;}
    const headline=d.complete?"✅ Seluruh rute selesai":`Tujuan berikutnya: ${d.next_name||"-"}`;
    box.innerHTML=`<div style="display:flex;justify-content:space-between;gap:8px;margin-top:9px;font-size:.78rem"><b>${headline}</b><span>${d.completed}/${d.total} · ${d.percent}%</span></div>
      <div class="route-progress"><span style="width:${d.percent}%"></span></div>
      <div style="font-size:.7rem;color:var(--tx3);margin-bottom:7px">Periode ${d.mulai} sampai ${d.selesai_jam}${d.enforced?" · wajib berurutan":" · urutan hanya panduan"}</div>
      ${d.items.map(x=>`<div class="route-step ${x.status}"><div style="font-size:1rem">${x.status==="selesai"?"✅":x.status==="berikutnya"?"📍":"○"}</div><div style="min-width:0"><b style="font-size:.82rem">${x.urutan}. ${x.nama}</b><div style="font-size:.71rem;color:var(--tx2)">${x.lokasi||"Lokasi belum diisi"}${x.status==="selesai"?` · ${x.waktu} oleh ${x.oleh||"anggota"}`:""}</div></div></div>`).join("")}`;
  }catch(e){box.innerHTML=`<p style="font-size:.8rem;color:var(--er);margin-top:10px">${e.message}</p>`;}
}
async function pinLocation(){
  const btn=document.getElementById("btn-pin-loc");
  btn.disabled=true;btn.innerHTML="⏳ Membaca GPS...";
  try{
    const g=await getGPS();patrolGPS=g;
    let nearest=null,minDist=Infinity,matched=null,matchedDist=Infinity,cps=[];
    try{
      cps=(await api("GET","/api/checkpoints")).filter(c=>c.tipe==="patrol");
      cps.filter(c=>c.lat!==null&&c.lon!==null).forEach(cp=>{
        const d=haversine(g.lat,g.lon,cp.lat,cp.lon),radius=Math.max(25,Math.min(1000,Number(cp.radius_meter)||30));
        if(d<minDist){minDist=d;nearest=cp;}
        if(d<=radius&&d<matchedDist){matchedDist=d;matched=cp;}
      });
    }catch(e){}
    document.getElementById("gps-idle").style.display="none";
    document.getElementById("gps-result").style.display="block";
    const wrap=document.getElementById("manual-pos-wrap"),help=document.getElementById("manual-pos-help"),select=document.getElementById("manual-pos");
    select.innerHTML="";const general=document.createElement("option");general.value="";general.textContent="Laporan lokasi umum";select.appendChild(general);
    cps.forEach(cp=>{const opt=document.createElement("option");opt.value=cp.id;opt.textContent=`${cp.urutan||"-"}. ${cp.nama}${cp.lokasi?" — "+cp.lokasi:""}`;select.appendChild(opt);});
    if(matched){
      patrolSelectedCP=matched.id;wrap.style.display="none";help.style.display="none";
      document.getElementById("gps-cp-name").textContent="📍 "+matched.nama;
      document.getElementById("gps-dist").textContent=`Terdeteksi otomatis · ±${Math.round(matchedDist)} m · radius ${matched.radius_meter||30} m`;
    }else{
      patrolSelectedCP=null;wrap.style.display="block";help.style.display="block";
      document.getElementById("gps-cp-name").textContent="📍 Lokasi GPS Dicatat";
      document.getElementById("gps-dist").textContent=nearest?`Di luar radius pos (terdekat ±${Math.round(minDist)} m: ${nearest.nama}) · pilih pos bila GPS kurang akurat`:"Pos berkoordinat belum tersedia · pilih pos secara manual";
    }
    document.getElementById("gps-coords-text").textContent=`${g.lat.toFixed(6)}, ${g.lon.toFixed(6)} (±${Math.round(g.acc||0)}m)`;
    document.getElementById("patrol-form").style.display="block";
    Snd.notif();toast("📍 Lokasi berhasil ditangkap!");
  }catch(e){toast(e.message,true,5000);}
  btn.disabled=false;btn.innerHTML="📍&nbsp; TANDAI LOKASI SAYA";
}
function resetPatrol(){
  patrolGPS=null;patrolSelectedCP=null;
  document.getElementById("gps-idle").style.display="block";document.getElementById("gps-result").style.display="none";
  document.getElementById("patrol-form").style.display="none";
  document.getElementById("manual-pos-wrap").style.display="none";document.getElementById("manual-pos-help").style.display="none";
  document.getElementById("manual-pos").innerHTML='<option value="">Laporan lokasi umum</option>';
  document.getElementById("inp-ket").value="";document.getElementById("inp-photo").value="";
  document.getElementById("pprev-grid").innerHTML="";document.getElementById("plabel").style.display="";
  document.getElementById("pbox").classList.remove("has");
}
async function prevPatrol(inp){
  const files=Array.from(inp.files||[]),grid=document.getElementById("pprev-grid");grid.innerHTML="";
  if(files.length>6){inp.value="";document.getElementById("plabel").style.display="";document.getElementById("pbox").classList.remove("has");toast("Maksimal 6 foto per laporan",true);return;}
  if(!files.length)return;
  files.forEach((file,i)=>{const img=document.createElement("img");img.alt=`Foto patroli ${i+1}`;img.src=URL.createObjectURL(file);img.onload=()=>URL.revokeObjectURL(img.src);grid.appendChild(img);});
  document.getElementById("plabel").style.display="none";document.getElementById("pbox").classList.add("has");
}
async function doPatrolGPS(){
  if(!patrolGPS){toast("Tandai lokasi terlebih dahulu",true);return;}
  const ket=document.getElementById("inp-ket").value.trim();
  if(!ket){toast("Isi keterangan situasi",true);return;}
  const photos=Array.from(document.getElementById("inp-photo").files||[]);
  const btn=document.getElementById("btn-patrol-submit");btn.disabled=true;btn.textContent="⏳ Mengirim...";
  try{
    const f=fd("lat",patrolGPS.lat,"lon",patrolGPS.lon,"keterangan",ket);
    const manualId=document.getElementById("manual-pos").value;
    if(patrolSelectedCP||manualId)f.append("selected_cp_id",patrolSelectedCP||manualId);
    const compressed=await Promise.all(photos.map(file=>compressImage(file)));
    compressed.forEach(file=>f.append("photos",file));
    const d=await api("POST","/api/patrol/gps",f);
    Snd.patrol();toast("📍 "+d.message);resetPatrol();await loadPatrolRoute();
  }catch(e){const msg=e.message.includes("|")?e.message.split("|").slice(1).join("|"):e.message;toast(msg,true,6000);if(e.message.startsWith("RUTE_BERURUTAN|")||e.message.startsWith("CHECKPOINT_SELESAI|")){resetPatrol();loadPatrolRoute();}}
  btn.disabled=false;btn.innerHTML="📤 Kirim Laporan";
}
async function loadCPPatrol(){
  const box=document.getElementById("cp-patrol");
  try{
    const cps=await api("GET","/api/checkpoints");const list=cps.filter(c=>c.tipe==="patrol");
    box.innerHTML=list.length?list.map(c=>`<div class="cp-row">
      <div><b style="font-size:.86rem">${c.urutan||"-"}. ${c.nama}</b><div style="font-size:.73rem;color:var(--tx2)">${c.lokasi||""}${c.lat!==null?` · GPS: ${c.lat.toFixed(4)}, ${c.lon.toFixed(4)}`:" · (Belum ada GPS)"} · Radius ${c.radius_meter||30} m</div></div>
      <span class="badge">${c.token||"GPS"}</span></div>`).join("")
      :`<p style="color:var(--tx2);font-size:.83rem">Belum ada pos patroli GPS.</p>`;
  }catch(e){box.innerHTML="";}
}

// ── WEB PUSH ──────────────────────────────────────────────
function vapidBytes(value){
  const pad="=".repeat((4-value.length%4)%4),raw=atob((value+pad).replace(/-/g,"+").replace(/_/g,"/"));
  return Uint8Array.from([...raw].map(c=>c.charCodeAt(0)));
}
async function getPushSubscription(){
  if(!("serviceWorker" in navigator)||!("PushManager" in window)||!("Notification" in window))return null;
  const reg=await navigator.serviceWorker.ready;return reg.pushManager.getSubscription();
}
async function syncPushState(registerExisting=false){
  const panel=document.getElementById("push-panel"),btn=document.getElementById("btn-push-toggle"),test=document.getElementById("btn-push-test"),desc=document.getElementById("push-desc");
  if(!panel)return;
  if(!window.isSecureContext||!("PushManager" in window)){desc.textContent="Web Push memerlukan HTTPS dan browser yang mendukung Push API.";btn.style.display="none";test.style.display="none";return;}
  try{
    const config=await api("GET","/api/push/config");if(!config.enabled){desc.textContent="Kunci Web Push server belum tersedia. Jalankan ulang installer.";btn.style.display="none";return;}
    const sub=await getPushSubscription(),active=!!sub;
    btn.style.display="";btn.textContent=active?"Nonaktifkan Web Push":"Aktifkan Web Push";btn.className=`btn btn-xs ${active?"btn-er":"btn-p"}`;btn.onclick=active?()=>disableWebPush():()=>enableWebPush();
    test.style.display=active?"":"none";desc.textContent=active?"Aktif — SOS, chat, dan tagihan dapat muncul saat aplikasi ditutup.":Notification.permission==="denied"?"Izin diblokir. Aktifkan notifikasi dari pengaturan situs browser.":"Tetap menerima SOS, chat, dan tagihan saat aplikasi ditutup.";
    if(active&&registerExisting)await api("POST","/api/push/subscribe",fd("subscription",JSON.stringify(sub.toJSON())));
  }catch(e){desc.textContent="Status Web Push belum dapat diperiksa: "+e.message;}
}
async function enableWebPush(){
  const btn=document.getElementById("btn-push-toggle");btn.disabled=true;btn.textContent="Mengaktifkan...";
  try{
    if(!window.isSecureContext)throw new Error("Buka aplikasi melalui HTTPS untuk mengaktifkan Web Push.");
    const permission=await Notification.requestPermission();if(permission!=="granted")throw new Error("Izin notifikasi belum diberikan.");
    const config=await api("GET","/api/push/config");if(!config.enabled||!config.public_key)throw new Error("Kunci Web Push server belum siap.");
    const reg=await navigator.serviceWorker.ready;let sub=await reg.pushManager.getSubscription();
    if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:vapidBytes(config.public_key)});
    const d=await api("POST","/api/push/subscribe",fd("subscription",JSON.stringify(sub.toJSON())));toast("✅ "+d.message);await syncPushState();
  }catch(e){toast(e.message,true,5000);await syncPushState();}
  btn.disabled=false;
}
async function disableWebPush(silent=false){
  const sub=await getPushSubscription();
  if(sub){try{await api("POST","/api/push/unsubscribe",fd("endpoint",sub.endpoint));}catch(e){if(!silent)throw e;}await sub.unsubscribe().catch(()=>{});}
  if(!silent){toast("Web Push dinonaktifkan.");await syncPushState();}
}
async function testWebPush(){try{const d=await api("POST","/api/push/test",fd());toast("🔔 "+d.message);}catch(e){toast(e.message,true,5000);}}
function handlePushTarget(target){
  pendingPushTarget=null;try{history.replaceState({},"",location.pathname);}catch(e){}
  const value=String(target||"").includes("push=")?new URL(target,location.origin).searchParams.get("push"):String(target||"");
  if(value==="chat"){
    goTab("grup");const btn=[...document.querySelectorAll(".gtab")].find(x=>x.getAttribute("onclick")?.includes("'chat'"));if(btn)gTab("chat",btn);
  }else if(value==="kompensasi"&&["koordinator","admin","super_admin"].includes(S.role)){
    goTab("grup");const btn=document.getElementById("gtab-kompensasi");if(btn)gTab("kompensasi",btn);
  }else if(value==="kompensasi"){goTab("home");setTimeout(()=>document.getElementById("kompensasi-home")?.scrollIntoView({behavior:"smooth",block:"center"}),250);}
  else{goTab("home");setTimeout(openNotifPanel,220);}
}

// ── NOTIF POLLING ─────────────────────────────────────────
function startNotifPoll(){if(notifPoll)clearInterval(notifPoll);pollNotifs();notifPoll=setInterval(pollNotifs,9000);}
async function pollNotifs(){
  if(!S.token)return;
  try{
    const params=lastNotifTime?`?since=${encodeURIComponent(lastNotifTime)}`:"";
    const d=await api("GET",`/api/notifications${params}`);
    const isFirst=!lastNotifTime;lastNotifTime=d.server_time;
    if(Array.isArray(d.active_ids)){
      const active=new Set(d.active_ids.map(String));
      document.querySelectorAll(".sos-popup[data-notif-id]").forEach(el=>{if(!active.has(el.dataset.notifId))el.remove();});
      document.querySelectorAll(".notif-item[data-notif-id]").forEach(el=>{if(!active.has(el.dataset.notifId))el.remove();});
    }
    // Update badge
    const badge=document.getElementById("notif-badge");
    if(d.unread>0){badge.style.display="block";badge.textContent=d.unread>9?"9+":d.unread;}
    else badge.style.display="none";
    // Sounds for new notifs
    if(!isFirst&&d.notifications&&d.notifications.length>0){
      const newest=d.notifications[0];
      if(newest.tipe==="sos"){Snd.sos();showSOSAlert(newest);}
      else if(newest.tipe==="chat"){if(activeTab!=="grup")Snd.chat();refreshChatBadge(true);}
      else if(newest.tipe==="checkin"||newest.tipe==="checkout"||newest.tipe==="attendance")Snd.checkin();
      else if(newest.tipe==="patrol")Snd.patrol();
      else if(newest.tipe==="invite"){Snd.invite();loadChatInvites();}
      else if(newest.tipe==="kompensasi")Snd.notif();
      else Snd.notif();
      const ni={sos:"🆘",chat:"💬",checkin:"✅",checkout:"🚩",attendance:"📝",patrol:"📍",invite:"📨",kompensasi:"💳"};
      toast(`${ni[newest.tipe]||"🔔"} ${newest.judul}${newest.pesan?" — "+newest.pesan:""}`,newest.tipe==="sos",5500);
      if(newest.tipe==="sos"){const sb=document.getElementById("sos-nb");if(sb)sb.style.display="block";}
    }
    if(activeTab==="home")loadStats();
  }catch(e){}
}
function showSOSAlert(notif){
  const el=document.createElement("div");el.className="sos-popup";
  el.dataset.notifId=notif.id;
  el.innerHTML=`<div class="sos-box"><div style="font-size:3rem;margin-bottom:10px">🆘</div>
    <h2 style="color:var(--er);margin-bottom:8px">SINYAL DARURAT!</h2>
    <p style="font-weight:700;margin-bottom:5px">${notif.judul}</p>
    <p style="color:#64748b;font-size:.85rem;margin-bottom:18px">${notif.pesan}</p>
    <button class="btn btn-er" onclick="this.closest('.sos-popup').remove()">Saya Mengerti</button></div>`;
  document.body.appendChild(el);Snd.sos();setTimeout(()=>{if(el.parentNode)el.remove();},15000);
}

async function openNotifPanel(){
  openMo("mo-notif");const box=document.getElementById("notif-list");
  syncPushState();
  box.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const d=await api("GET","/api/notifications");
    if(!d.notifications.length){box.innerHTML=`<p style="text-align:center;color:var(--tx2);padding:16px">Tidak ada notifikasi.</p>`;return;}
    const icons={checkin:"✅",checkout:"🚩",attendance:"📝",patrol:"📍",chat:"💬",sos:"🆘",system:"⚙️",invite:"📨",kompensasi:"💳"};
    box.innerHTML=d.notifications.map(n=>`
      <div class="notif-item ${n.tipe==="sos"?"sos":""} ${!n.dibaca?"unread":""}" data-notif-id="${n.id}">
        <button class="notif-del" onclick="deleteNotif(${n.id},this)" title="Hapus">✕</button>
        <div style="font-weight:700;font-size:.86rem;padding-right:24px">${icons[n.tipe]||"🔔"} ${n.judul}</div>
        <div style="font-size:.78rem;color:var(--tx2);margin-top:2px">${n.pesan}</div>
        <div style="font-size:.68rem;color:var(--tx3);margin-top:3px">${n.timestamp?.slice(11,16)||""}</div>
      </div>`).join("");
    // Mark all as read
    api("POST","/api/notifications/read",fd()).then(()=>{
      const badge=document.getElementById("notif-badge");badge.style.display="none";
    }).catch(()=>{});
  }catch(e){box.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
async function markAllRead(){
  try{await api("POST","/api/notifications/read",fd());document.getElementById("notif-badge").style.display="none";openNotifPanel();}catch(e){}
}
async function deleteNotif(id,btn){
  try{await api("DELETE",`/api/notifications/${id}`);const item=btn.closest(".notif-item");if(item)item.remove();}catch(e){}
  await pollNotifs();
}
async function deleteAllNotifs(){
  showConfirm("Hapus Semua Notifikasi","Hapus semua notifikasi?",async()=>{
    try{await api("DELETE","/api/notifications");openNotifPanel();pollNotifs();}catch(e){}
  },"Ya, Hapus Semua",true);
}

// ── SOS ───────────────────────────────────────────────────
async function sendSOS(){
  const ket=document.getElementById("sos-ket").value||"Butuh bantuan segera!";
  try{toast("📡 Membaca GPS darurat...",false,8000);const g=await getGPS(5000);
    const d=await api("POST","/api/emergency/sos",fd("lat",g.lat,"lon",g.lon,"keterangan",ket));
    Snd.sos();toast("🆘 "+d.message,false,6000);closeMo("mo-sos");
  }catch(e){toast(e.message,true,5000);}
}

// ── GRUP INFO ─────────────────────────────────────────────
async function loadGrupInfo(){
  try{
    const d=await api("GET","/api/group/info");
    const t=document.getElementById("grup-nama-title");if(t)t.textContent=d.nama||`Grup ${S.grup}`;
  }catch(e){}
}

// ── GRUP: ANGGOTA ─────────────────────────────────────────
function gTab(name,btn){
  ["anggota","chat","jadwal","kompensasi"].forEach(k=>{const el=document.getElementById("gsub-"+k);if(el)el.style.display="none";});
  document.querySelectorAll(".gtab").forEach(b=>b.classList.remove("active"));
  const el=document.getElementById("gsub-"+name);if(el){el.style.display="";el.style.animation="slide-up .22s ease";}
  document.querySelector("#view-grup .con")?.classList.toggle("chat-mode",name==="chat");
  btn.classList.add("active");
  if(name==="chat"){startChatPoll();loadChatInvites();markChatRead();setTimeout(syncChatLayout,40);}
  if(name==="jadwal")loadGrupJadwal();
  if(name==="kompensasi")loadKompensasi("group-komp-list","group");
}
async function loadMembers(){
  const box=document.getElementById("member-list");
  box.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const d=await api("GET","/api/group/members");
    const badgeEl=document.getElementById("grup-jadwal-badge");
    if(badgeEl)badgeEl.innerHTML=d.jadwal_hari_ini?`<span class="jadwal-chip active" style="font-size:.72rem;padding:4px 10px">✅ Berjadwal Hari Ini</span>`:
      `<span class="jadwal-chip inactive" style="font-size:.72rem;padding:4px 10px">❌ Tidak Berjadwal Hari Ini</span>`;
    if(!d.members.length){box.innerHTML=`<p style="color:var(--tx2)">Tidak ada anggota di grup ini.</p>`;return;}
    const stLbl={in:"Sudah Check-IN",out:"Sudah Check-OUT",belum:"Belum Absen"};
    box.innerHTML=d.members.map(m=>`<div class="member-card">
      ${avatar(m.nama,m.foto,42)}
      <div style="flex:1;min-width:0">
        <div style="font-weight:800;font-size:.88rem;display:flex;align-items:center;gap:6px;flex-wrap:wrap">
          ${m.nama}
          ${m.role==="koordinator"?`<span class="badge badge-ko">Koordinator</span>`:""}
          ${m.role==="admin"||m.role==="super_admin"?`<span class="badge">Admin</span>`:""}
        </div>
        <div style="font-size:.74rem;color:var(--tx2);margin-top:2px">${stLbl[m.status]||"Belum Absen"}</div>
      </div>
      <div class="m-dot ${m.status}"></div>
    </div>`).join("");
  }catch(e){box.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}

// ── CHAT ─────────────────────────────────────────────────
function refreshChatBadge(show){const b=document.getElementById("chat-badge");if(b)b.style.display=show?"block":"none";}
async function loadChatRooms(){
  try{const rooms=await api("GET","/api/group/chat/rooms"),sel=document.getElementById("chat-room"),wrap=document.getElementById("chat-room-wrap");
    if(!rooms.some(r=>String(r.grup_id)===String(currentChatRoom)))currentChatRoom="0";
    sel.innerHTML=rooms.map(r=>`<option value="${r.grup_id}" ${String(r.grup_id)===String(currentChatRoom)?"selected":""}>${r.umum?"🌐":"💬"} ${r.nama}${r.utama?" (Grup Saya)":(!r.umum?" (Undangan)":"")}</option>`).join("");wrap.style.display=rooms.length>1?"block":"none";
    localStorage.setItem("sk_chat_room",currentChatRoom);setTimeout(syncChatLayout,30);
  }catch(e){}
}
function switchChatRoom(room){currentChatRoom=String(room);localStorage.setItem("sk_chat_room",currentChatRoom);lastChatTime=null;cancelReply();loadChat();}
function startChatPoll(){stopChatPoll();loadChat();chatPoll=setInterval(pollChat,5000);}
function stopChatPoll(){if(chatPoll){clearInterval(chatPoll);chatPoll=null;}}
async function markChatRead(){
  try{const d=await api("POST","/api/notifications/read/chat",fd());refreshChatBadge(false);const badge=document.getElementById("notif-badge");if(d.unread===0)badge.style.display="none";else{badge.style.display="block";badge.textContent=d.unread>9?"9+":d.unread;}}catch(e){}
}

async function loadChat(){
  const box=document.getElementById("chat-msgs");if(!box)return;
  box.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{const d=await api("GET",`/api/group/chat?room_id=${encodeURIComponent(currentChatRoom||S.grup)}`);lastChatTime=d.server_time;renderChat(d.messages);scrollChat();}
  catch(e){box.innerHTML=`<p style="color:var(--er);text-align:center;padding:16px">${e.message}</p>`;}
}

async function pollChat(){
  if(!S.token||activeTab!=="grup")return;
  try{
    const params=new URLSearchParams({room_id:String(currentChatRoom||S.grup)});if(lastChatTime)params.set("since",lastChatTime);
    const d=await api("GET",`/api/group/chat?${params}`);lastChatTime=d.server_time;
    if(d.messages.length>0){appendChatMsgs(d.messages);scrollChat();if(d.messages.some(m=>!m.is_mine&&m.tipe!=="deleted"))Snd.chat();}
  }catch(e){}
}

function renderChat(msgs){
  const box=document.getElementById("chat-msgs");
  if(!msgs.length){box.innerHTML=`<p style="text-align:center;color:var(--tx2);padding:24px;font-size:.85rem">Belum ada pesan. Mulai percakapan!</p>`;return;}
  box.innerHTML="";appendChatMsgs(msgs);
}
function appendChatMsgs(msgs){
  const box=document.getElementById("chat-msgs");
  msgs.forEach(m=>{
    if(document.querySelector(`.bw[data-id="${m.id}"]`))return; // skip duplicate
    if(m.tipe==="system"){
      const el=document.createElement("div");el.style.cssText="text-align:center;padding:6px 0";
      const sys=document.createElement("span");sys.className="bubble system-msg";sys.textContent=m.pesan;el.appendChild(sys);box.appendChild(el);return;
    }
    const wrap=document.createElement("div");
    wrap.className=`bw ${m.is_mine?"mine":""}`;wrap.dataset.id=m.id;wrap.dataset.mine=m.is_mine;
    const avEl=document.createElement("div");avEl.className="bav";
    if(m.foto)avEl.innerHTML=`<img src="/uploads/profile/${m.foto}" onerror="this.style.display='none'">`;
    else avEl.textContent=m.nama?m.nama.charAt(0).toUpperCase():"?";
    const meta=document.createElement("div");meta.className="bmeta";
    if(!m.is_mine){const bn=document.createElement("div");bn.className="bname";bn.textContent=m.nama;meta.appendChild(bn);}
    const bubble=document.createElement("div");
    if(m.is_deleted){
      bubble.className="bubble deleted";bubble.textContent="🚫 Pesan dihapus";
    }else{
      bubble.className=`bubble ${m.is_mine?"mine":"theirs"}`;
      if(m.reply_preview){const rp=document.createElement("div");rp.className="breply";rp.textContent="↩ "+m.reply_preview;bubble.appendChild(rp);bubble.appendChild(document.createTextNode(m.pesan));}
      else bubble.textContent=m.pesan;
      if(Array.isArray(m.media)&&m.media.length){
        const gallery=document.createElement("div");gallery.className=`chat-media ${m.media.length===1?"one":""}`;
        m.media.forEach((path,i)=>{const img=document.createElement("img");img.loading="lazy";img.alt=`Foto patroli ${i+1}`;
          img.src="/uploads/ronda/"+encodeURIComponent(path);img.onclick=e=>{e.stopPropagation();showChatPhoto(path);};gallery.appendChild(img);});
        bubble.appendChild(gallery);
      }
    }
    const btime=document.createElement("div");btime.className="btime";btime.textContent=m.waktu;
    meta.appendChild(bubble);meta.appendChild(btime);
    // Action buttons
    if(!m.is_deleted){
      const acts=document.createElement("div");acts.className="bactions";
      const reply=document.createElement("button");reply.className="baction-btn";reply.textContent="↩ Reply";reply.onclick=()=>replyTo(m.id,m.pesan||"",m.nama||"");acts.appendChild(reply);
      if(m.is_mine){const del=document.createElement("button");del.className="baction-btn del";del.textContent="🗑";del.onclick=()=>deleteMsg(m.id);acts.appendChild(del);}
      meta.appendChild(acts);
    }
    if(m.is_mine){wrap.appendChild(meta);wrap.appendChild(avEl);}
    else{wrap.appendChild(avEl);wrap.appendChild(meta);}
    box.appendChild(wrap);
  });
}
function showChatPhoto(path){
  const viewer=document.createElement("div");viewer.className="photo-viewer";viewer.tabIndex=0;
  const img=document.createElement("img");img.alt="Foto patroli";img.src="/uploads/ronda/"+encodeURIComponent(path);
  const close=document.createElement("button");close.type="button";close.textContent="✕";close.setAttribute("aria-label","Tutup foto");
  const dismiss=()=>viewer.remove();close.onclick=e=>{e.stopPropagation();dismiss();};viewer.onclick=dismiss;
  viewer.onkeydown=e=>{if(e.key==="Escape")dismiss();};viewer.appendChild(img);viewer.appendChild(close);document.body.appendChild(viewer);viewer.focus();
}
function syncChatLayout(){
  const wrap=document.querySelector("#gsub-chat .chat-wrapper");if(!wrap||document.getElementById("gsub-chat")?.style.display==="none")return;
  const viewport=window.visualViewport,viewHeight=viewport?viewport.height:window.innerHeight;
  const keyboardOpen=!!viewport&&viewport.height<window.innerHeight-120;
  const bottomGap=window.innerWidth>=900?18:(keyboardOpen?4:(document.getElementById("bnav")?.offsetHeight||64)+4);
  const top=Math.max(0,wrap.getBoundingClientRect().top-(viewport?.offsetTop||0));
  const minHeight=keyboardOpen?140:(window.innerWidth>=900?480:300);wrap.style.minHeight=minHeight+"px";
  wrap.style.height=Math.max(minHeight,Math.floor(viewHeight-top-bottomGap))+"px";
}
function scrollChat(){const box=document.getElementById("chat-msgs");if(box)setTimeout(()=>{syncChatLayout();box.scrollTop=box.scrollHeight;},60);}
window.addEventListener("resize",syncChatLayout,{passive:true});
if(window.visualViewport){window.visualViewport.addEventListener("resize",syncChatLayout,{passive:true});window.visualViewport.addEventListener("scroll",syncChatLayout,{passive:true});}

function autoResize(el){el.style.height="auto";el.style.height=Math.min(el.scrollHeight,100)+"px";syncChatLayout();}

// Reply
function replyTo(id,pesan,nama){
  replyTarget={id,pesan,nama};
  const bar=document.getElementById("reply-bar"),pt=document.getElementById("reply-preview-text");
  pt.textContent=`${nama}: ${pesan}`;bar.classList.add("show");
  document.getElementById("chat-inp").focus();
}
function cancelReply(){replyTarget=null;document.getElementById("reply-bar").classList.remove("show");}

async function sendChat(){
  const inp=document.getElementById("chat-inp"),msg=inp.value.trim();if(!msg)return;
  inp.value="";inp.style.height="auto";inp.focus();
  const f=fd("pesan",msg,"room_id",currentChatRoom||S.grup);if(replyTarget)f.append("reply_to_id",replyTarget.id);
  cancelReply();
  try{await api("POST","/api/group/chat",f);await pollChat();}
  catch(e){toast(e.message,true);inp.value=msg;}
}

async function deleteMsg(id){
  showConfirm("Hapus Pesan","Hapus pesan ini? Akan hilang untuk semua anggota.",async()=>{
    try{await api("DELETE",`/api/group/chat/${id}`);
      const el=document.querySelector(`.bw[data-id="${id}"]`);
      if(el){const b=el.querySelector(".bubble");if(b){b.className="bubble deleted";b.innerHTML="🚫 Pesan dihapus";const acts=el.querySelector(".bactions");if(acts)acts.remove();}}
    }catch(e){toast(e.message,true);}
  },"Ya, Hapus",true);
}

async function loadChatInvites(){
  try{
    const d=await api("GET","/api/group/chat/invites");
    const sec=document.getElementById("invite-section"),list=document.getElementById("invite-list");
    if(!sec||!list)return;
    if(!d.invites.length){sec.style.display="none";return;}
    sec.style.display="block";
    list.innerHTML=d.invites.map(inv=>`<div style="background:var(--bg);border-radius:var(--r2);padding:11px;margin-bottom:7px;border-left:3px solid var(--pu)">
      <b>${inv.dari}</b> mengundang Anda ke chat Grup ${inv.grup_id}
      <div style="font-size:.73rem;color:var(--tx2)">${inv.waktu}</div>
      <div style="display:flex;gap:7px;margin-top:9px">
        <button class="btn btn-ok btn-sm" onclick="respondInvite(${inv.id},true)">✅ Terima</button>
        <button class="btn btn-ghost btn-sm" onclick="respondInvite(${inv.id},false)">❌ Tolak</button>
      </div></div>`).join("");
  }catch(e){}
}
async function respondInvite(id,accept){
  try{const d=await api("PUT",`/api/group/chat/invite/${id}`,fd("accept",accept));toast(d.message);Snd.notif();loadChatInvites();if(accept){await loadChatRooms();loadChat();}}
  catch(e){toast(e.message,true);}
}
async function sendInvite(){
  const hp=document.getElementById("invite-hp").value.trim();if(!hp){toast("Isi ID warga atau No. HP",true);return;}
  try{const d=await api("POST","/api/group/chat/invite",fd("target_hp",hp));Snd.notif();toast(d.message);document.getElementById("invite-hp").value="";}
  catch(e){toast(e.message,true);}
}

async function loadGrupJadwal(){
  const box=document.getElementById("jadwal-list");if(!box)return;
  box.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const d=await api("GET","/api/group/schedule");
    const today=new Date().getDay()===0?6:new Date().getDay()-1;
    if(!d.length){box.innerHTML=`<p style="color:var(--tx2)">Belum ada jadwal. Hubungi Admin.</p>`;return;}
    box.innerHTML=d.map(j=>`<div style="display:flex;justify-content:space-between;align-items:center;padding:10px;background:var(--bg);border-radius:var(--r2);margin-bottom:7px;${j.hari===today?"border-left:3px solid var(--ok)":""}">
      <div><b style="font-size:.88rem">${j.hari_nama}</b>${j.tanggal?` <span style="font-size:.74rem;color:var(--tx2)">(${j.tanggal})</span>`:""}${j.catatan?`<div style="font-size:.76rem;color:var(--tx2)">${j.catatan}</div>`:""}</div>
      ${j.hari===today?`<span class="badge badge-ok">Hari Ini</span>`:""}</div>`).join("");
  }catch(e){box.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}

// ── ADMIN ─────────────────────────────────────────────────
function aTab(id,btn){
  ["adash","awarga","aabsen","agrup","acp","aset","ajadwal","apengganti","akompensasi","adata","alap","asos","alog"].forEach(k=>{const el=document.getElementById(k);if(el)el.style.display="none";});
  document.querySelectorAll(".atab").forEach(b=>b.classList.remove("active"));
  const el=document.getElementById(id);if(el){el.style.display="";el.style.animation="slide-up .22s ease";}
  btn.classList.add("active");
  if(id==="adash")loadAdminStats();if(id==="awarga")loadWarga();if(id==="agrup")loadAdminGroups();
  if(id==="acp")loadCPAdmin();if(id==="aset")loadSettings();if(id==="ajadwal")loadAllSchedules();
  if(id==="aabsen"){loadWargaDropdowns().then(()=>populateManualWarga());loadManualAttendance();}
  if(id==="apengganti"){loadPengganti();loadWargaDropdowns();}if(id==="akompensasi")loadKompensasi("admin-komp-list","admin");if(id==="adata")loadDataSets();if(id==="asos")loadSOS();if(id==="alog")loadAudit();
}

async function loadAdminStats(){
  const g=document.getElementById("adsg");g.innerHTML=`<div class="loading" style="grid-column:1/-1"><div class="spin"></div></div>`;
  try{
    const d=await api("GET","/api/admin/stats");
    g.innerHTML=[["👥",d.total_warga,"Total Warga"],["🔢",d.total_grup,"Grup Aktif"],
      ["✅",d.absen_hari_ini,"Absen Hari Ini"],["📅",d.absen_bulan_ini,"Absen Bulan Ini"],
      ["📍",d.patroli_hari_ini,"Patroli Hari Ini"],["📊",d.patroli_bulan_ini,"Patroli Bulan Ini"],
      ["🆘",d.emergency_aktif,"Alert SOS Aktif"],["💳",d.kompensasi_belum||0,"Kompensasi Belum Lunas"],["📌",d.total_checkpoint,"Checkpoint Aktif"],
    ].map(([ic,vl,lb])=>`<div class="sc"><div style="font-size:1.6rem">${ic}</div><div class="sn" style="font-size:1.5rem;margin-top:4px">${vl}</div><div class="sl">${lb}</div></div>`).join("");
  }catch(e){g.innerHTML=`<p style="color:var(--er);grid-column:1/-1">${e.message}</p>`;}
}

// ── ADMIN: WARGA ──────────────────────────────────────────
let allW=[];
async function loadWarga(){
  const b=document.getElementById("wlist");b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{allW=await api("GET","/api/admin/warga");renderW(allW);}
  catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
function renderW(list){
  const b=document.getElementById("wlist");
  if(!list.length){b.innerHTML=`<p style="color:var(--tx2)">Belum ada warga.</p>`;return;}
  b.innerHTML=list.map(w=>`<div class="wi">
    ${avatar(w.nama,w.foto,40)}
    <div style="flex:1;min-width:0">
      <div style="font-weight:800;font-size:.86rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${w.nama}</div>
      <div style="font-size:.72rem;color:var(--tx2)">ID ${w.akun_id||"-"} · ${w.no_hp} · Grup ${w.grup_id}
        <span class="badge">${w.role}</span>${!w.is_active?`<span class="badge badge-er">nonaktif</span>`:""}</div>
    </div>
    <button class="btn btn-xs btn-ghost" onclick='openEW(${JSON.stringify(w)})'>✏️</button>
  </div>`).join("");
}
function filterW(q){renderW(allW.filter(w=>w.nama.toLowerCase().includes(q.toLowerCase())||w.no_hp.includes(q)||(w.akun_id||"").includes(q)||String(w.grup_id).includes(q)));}
function openEW(w){
  document.getElementById("ew-id").value=w.id;document.getElementById("ew-nama").value=w.nama;
  document.getElementById("ew-aid").value=w.akun_id||"";
  document.getElementById("ew-hp").value=w.no_hp;document.getElementById("ew-lahir").value=w.tanggal_lahir||"";
  document.getElementById("ew-grup").value=w.grup_id;document.getElementById("ew-role").value=w.role;
  document.getElementById("ew-cat").value=w.catatan||"";document.getElementById("ew-act").checked=w.is_active;
  openMo("mo-ew");
}
async function saveEW(){
  const wid=document.getElementById("ew-id").value;
  try{
    const d=await api("PUT",`/api/admin/warga/${wid}`,fd(
      "nama",document.getElementById("ew-nama").value,
      "akun_id",document.getElementById("ew-aid").value,
      "no_hp",document.getElementById("ew-hp").value,
      "tanggal_lahir",document.getElementById("ew-lahir").value,
      "grup_id",document.getElementById("ew-grup").value,
      "role",document.getElementById("ew-role").value,
      "catatan",document.getElementById("ew-cat").value,
      "is_active",document.getElementById("ew-act").checked));
    toast("✅ "+d.message);closeMo("mo-ew");loadWarga();
  }catch(e){toast(e.message,true);}
}
async function addWarga(){
  const nama=document.getElementById("nw-nama").value.trim(),hp=document.getElementById("nw-hp").value.trim();
  const lahir=document.getElementById("nw-lahir").value.trim(),grup=document.getElementById("nw-grup").value;
  const role=document.getElementById("nw-role").value;
  if(!nama||!hp||!lahir||!grup||!role){toast("Isi semua kolom wajib",true);return;}
  try{
    const d=await api("POST","/api/admin/warga",fd("nama",nama,"akun_id",document.getElementById("nw-aid").value,"no_hp",hp,"tanggal_lahir",lahir,"grup_id",grup,"role",role,"catatan",document.getElementById("nw-cat").value));
    toast("✅ "+d.message);["nw-nama","nw-aid","nw-hp","nw-lahir","nw-grup","nw-cat"].forEach(id=>document.getElementById(id).value="");
    document.getElementById("nw-role").value="";loadWarga();
  }catch(e){toast(e.message,true);}
}
async function resetDev(){
  const hp=document.getElementById("reset-hp").value.trim();if(!hp){toast("Isi ID warga atau No. HP",true);return;}
  showConfirm("Reset Perangkat",`Reset perangkat akun <b>${hp}</b>?`,async()=>{
    try{const d=await api("POST","/api/auth/reset-device",fd("target_hp",hp));toast("🔓 "+d.message);document.getElementById("reset-hp").value="";}
    catch(e){toast(e.message,true);}
  },"Ya, Reset",true);
}
async function resetPass(){
  const ident=document.getElementById("reset-pass-id").value.trim();if(!ident){toast("Isi ID warga atau No. HP",true);return;}
  showConfirm("Reset Password",`Reset password akun <b>${ident}</b>?`,async()=>{
    try{const d=await api("POST","/api/auth/reset-password",fd("target_identifier",ident));toast("🔑 "+d.message);document.getElementById("reset-pass-id").value="";}
    catch(e){toast(e.message,true);}
  },"Ya, Reset",true);
}

function populateManualWarga(){
  const el=document.getElementById("ma-warga");if(!el)return;
  el.innerHTML=`<option value="">Pilih warga...</option>`+wargaList.map(w=>`<option value="${w.id}">[${w.akun_id}] Grup ${w.grup_id} — ${w.nama}</option>`).join("");
  const dt=document.getElementById("ma-tgl");if(dt&&!dt.value)dt.value=new Date().toISOString().slice(0,10);
}
async function saveManualAttendance(){
  const warga=document.getElementById("ma-warga").value,tgl=document.getElementById("ma-tgl").value,status=document.getElementById("ma-status").value;
  if(!warga||!tgl){toast("Pilih warga dan tanggal",true);return;}
  try{const d=await api("POST","/api/admin/attendance/manual",fd("warga_id",warga,"tanggal",tgl,"status",status,"keterangan",document.getElementById("ma-ket").value,"jam_masuk",document.getElementById("ma-in").value,"jam_keluar",document.getElementById("ma-out").value));toast("✅ "+d.message);loadManualAttendance();}
  catch(e){toast(e.message,true);}
}
async function loadManualAttendance(){
  const b=document.getElementById("manual-att-list"),dt=document.getElementById("ma-tgl");if(!b||!dt)return;if(!dt.value)dt.value=new Date().toISOString().slice(0,10);
  b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{const rows=await api("GET",`/api/admin/attendance?tanggal=${encodeURIComponent(dt.value)}`);b.innerHTML=rows.length?rows.map(a=>`<div class="wi"><div style="flex:1"><b>${a.nama}</b> <span class="badge">${a.akun_id}</span><div style="font-size:.75rem;color:var(--tx2)">Grup ${a.grup_id} · ${a.status.toUpperCase()} ${a.check_in?`· ${a.check_in}${a.check_out?`–${a.check_out}`:""}`:""}${a.keterangan?`<br>${a.keterangan}`:""}</div></div><span class="badge ${a.status==="hadir"?"badge-ok":"badge-wa"}">${a.manual?"Manual":"QR"}</span></div>`).join(""):`<p style="color:var(--tx2)">Belum ada absensi pada tanggal ini.</p>`;}
  catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}

// ── ADMIN: GRUP ───────────────────────────────────────────
async function loadAdminGroups(){
  const b=document.getElementById("group-list");b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const grups=await api("GET","/api/admin/groups");
    if(!grups.length){b.innerHTML=`<p style="color:var(--tx2)">Belum ada grup aktif.</p>`;return;}
    b.innerHTML=grups.map(g=>`<div class="group-card">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:5px">
        <div><b>Grup ${g.grup_id}: ${g.nama}</b></div>
        <button class="btn btn-xs btn-ghost" onclick="openGroupEdit(${g.grup_id},'${(g.nama||"").replace(/'/g,"\\'")}','${(g.deskripsi||"").replace(/'/g,"\\'")}')">✏️</button>
      </div>
      <div style="font-size:.78rem;color:var(--tx2)">👥 ${g.jumlah_anggota} anggota · 📅 ${g.jumlah_jadwal} jadwal</div>
      ${g.deskripsi?`<div style="font-size:.78rem;color:var(--tx2);margin-top:3px">${g.deskripsi}</div>`:""}
    </div>`).join("");
  }catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
function openGroupEdit(gid,nama,deskripsi){
  document.getElementById("eg-id").value=gid;document.getElementById("eg-num").textContent=gid;
  document.getElementById("eg-nama").value=nama;document.getElementById("eg-desk").value=deskripsi;
  openMo("mo-group-edit");
}
async function saveGroup(){
  const gid=document.getElementById("eg-id").value,nama=document.getElementById("eg-nama").value.trim();
  if(!nama){toast("Isi nama grup",true);return;}
  try{
    const d=await api("PUT",`/api/admin/group/${gid}`,fd("nama",nama,"deskripsi",document.getElementById("eg-desk").value));
    toast("✅ "+d.message);closeMo("mo-group-edit");loadAdminGroups();
  }catch(e){toast(e.message,true);}
}

// ── ADMIN: CHECKPOINT ─────────────────────────────────────
async function loadCPAdmin(){
  const b=document.getElementById("cplist");b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const cps=await api("GET","/api/admin/checkpoints");
    const TL={checkin:"✅ Check-IN",checkout:"🚩 Check-OUT",patrol:"📍 Patroli"};
    b.innerHTML=cps.map(c=>`<div class="admin-cp-card">
      <div style="min-width:0">
        <div class="admin-cp-title">${c.tipe==="patrol"?`<span class="admin-cp-route">Rute ${c.urutan}</span>`:""}<span class="admin-cp-name">${c.nama}</span><span class="badge">${c.token}</span>${!c.is_active?`<span class="badge badge-er">nonaktif</span>`:""}</div>
        <div class="admin-cp-meta">${TL[c.tipe]||c.tipe}${c.lokasi?" · "+c.lokasi:""}${c.lat!==null?` · GPS: ${c.lat.toFixed(4)}, ${c.lon.toFixed(4)}`:" · GPS belum diisi"}${c.tipe==="patrol"?` · Radius ${c.radius_meter||30} m`:""}</div>
      </div>
      <div class="admin-cp-actions">${c.tipe==="patrol"?`<button class="btn btn-xs btn-ghost" onclick="moveCP(${c.id},'up')" title="Naikkan urutan">↑ Naik</button><button class="btn btn-xs btn-ghost" onclick="moveCP(${c.id},'down')" title="Turunkan urutan">↓ Turun</button><button class="btn btn-xs btn-ghost" onclick="setCPRadius(${c.id},${c.radius_meter||30})">📡 Radius</button>`:""}<button class="btn btn-xs ${c.is_active?"btn-ghost":"btn-ok"}" onclick="toggleCP(${c.id},${!c.is_active})">${c.is_active?"Nonaktif":"Aktifkan"}</button></div>
    </div>`).join("");
  }catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
async function toggleCP(id,aktif){try{const d=await api("PUT",`/api/admin/checkpoint/${id}`,fd("is_active",aktif));toast(d.message);loadCPAdmin();}catch(e){toast(e.message,true);}}
async function moveCP(id,direction){try{const d=await api("POST",`/api/admin/checkpoint/${id}/move`,fd("direction",direction));toast(d.message);loadCPAdmin();}catch(e){toast(e.message,true);}}
async function setCPRadius(id,current){
  const value=prompt("Radius pos dalam meter (25–1000):",current);if(value===null)return;
  const radius=Number(value);if(!Number.isInteger(radius)||radius<25||radius>1000){toast("Radius harus angka bulat 25–1000 meter",true);return;}
  try{const d=await api("PUT",`/api/admin/checkpoint/${id}`,fd("radius_meter",radius));toast("✅ "+d.message);loadCPAdmin();}catch(e){toast(e.message,true);}
}
async function addCP(){
  const nama=document.getElementById("nc-nama").value.trim(),tok=document.getElementById("nc-tok").value.trim().toUpperCase();
  if(!nama||!tok){toast("Nama dan Token wajib",true);return;}
  try{
    const d=await api("POST","/api/admin/checkpoint",fd("nama",nama,"token",tok,"tipe",document.getElementById("nc-tipe").value,"lokasi",document.getElementById("nc-lok").value,"lat",document.getElementById("nc-lat").value||null,"lon",document.getElementById("nc-lon").value||null,"urutan",document.getElementById("nc-order").value||null,"radius_meter",document.getElementById("nc-radius").value||30));
    toast("✅ "+d.message);["nc-nama","nc-tok","nc-lok","nc-lat","nc-lon","nc-order"].forEach(id=>document.getElementById(id).value="");document.getElementById("nc-radius").value="30";loadCPAdmin();
  }catch(e){toast(e.message,true);}
}

// ── ADMIN: SETTINGS ───────────────────────────────────────
async function loadSettings(){
  const b=document.getElementById("setlist");b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const sets=await api("GET","/api/admin/settings");
    b.innerHTML=sets.map(s=>`<div class="set-row">
      <span class="set-label">${s.label}</span>
      <div class="set-ctrl">
        ${s.key==="retensi_foto_hari"?`<select id="s-${s.key}"><option value="3" ${s.value==="3"?"selected":""}>3 hari</option><option value="7" ${s.value==="7"?"selected":""}>7 hari (default)</option><option value="14" ${s.value==="14"?"selected":""}>14 hari</option><option value="manual" ${s.value==="manual"?"selected":""}>Manual / tidak otomatis</option></select>`:`<input type="text" id="s-${s.key}" value="${s.value}">`}
        <button class="btn btn-xs btn-p" onclick="saveSetting('${s.key}','s-${s.key}')">Simpan</button>
      </div></div><div class="div" style="margin:8px 0"></div>`).join("");
  }catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
async function saveSetting(key,inputId){
  try{const d=await api("POST","/api/admin/settings",fd("key",key,"value",document.getElementById(inputId).value.trim()));toast("✅ "+d.message);}
  catch(e){toast(e.message,true);}
}

// ── ADMIN: JADWAL ─────────────────────────────────────────
async function loadAllSchedules(){
  const b=document.getElementById("all-schedules");b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const d=await api("GET","/api/admin/schedules");const grups=Object.keys(d).sort((a,b)=>+a-+b);
    if(!grups.length){b.innerHTML=`<p style="color:var(--tx2)">Belum ada jadwal.</p>`;return;}
    b.innerHTML=grups.map(gid=>`<div style="background:var(--bg);border-radius:var(--r2);padding:11px;margin-bottom:9px">
      <div style="font-weight:800;font-size:.86rem;margin-bottom:7px">Grup ${gid}
        ${d[gid].length?`<span class="badge" style="margin-left:5px">${d[gid].length} jadwal</span>`:""}
      </div>
      ${d[gid].length?d[gid].map(j=>`<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:5px;font-size:.82rem">
          <span>${j.hari_nama}${j.tanggal?` (${j.tanggal})`:""} ${j.catatan?`<span style="color:var(--tx2)">${j.catatan}</span>`:""}</span>
          <span style="display:flex;gap:4px"><button class="btn btn-xs btn-ghost" onclick="openEditJadwal('${encodeURIComponent(JSON.stringify({...j,grup_id:+gid}))}')">✏️</button><button class="btn btn-xs btn-er" onclick="delJadwal(${j.id})">🗑</button></span></div>`).join("")
        :`<p style="font-size:.8rem;color:var(--tx2)">Belum ada jadwal</p>`}
    </div>`).join("");
  }catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
async function addJadwal(){
  const grup=document.getElementById("jd-grup").value,hari=document.getElementById("jd-hari").value,tgl=document.getElementById("jd-tgl").value;
  if(!grup){toast("Isi nomor grup",true);return;}if(!hari&&!tgl){toast("Pilih hari atau tanggal",true);return;}
  try{
    const d=await api("POST","/api/admin/schedule",fd("grup_id",grup,"hari",hari||null,"tanggal",tgl||null,"catatan",document.getElementById("jd-cat").value));
    toast("✅ "+d.message);["jd-grup","jd-cat","jd-tgl"].forEach(id=>document.getElementById(id).value="");document.getElementById("jd-hari").value="";loadAllSchedules();
  }catch(e){toast(e.message,true);}
}
function openEditJadwal(encoded){
  const j=JSON.parse(decodeURIComponent(encoded));
  document.getElementById("ej-id").value=j.id;document.getElementById("ej-grup").value=j.grup_id;
  document.getElementById("ej-hari").value=j.hari===null||j.hari===undefined?"":String(j.hari);
  document.getElementById("ej-tgl").value=j.tanggal||"";document.getElementById("ej-cat").value=j.catatan||"";openMo("mo-schedule-edit");
}
async function saveEditJadwal(){
  const id=document.getElementById("ej-id").value,grup=document.getElementById("ej-grup").value,hari=document.getElementById("ej-hari").value,tgl=document.getElementById("ej-tgl").value;
  if(!grup||(!hari&&!tgl)){toast("Isi grup serta hari atau tanggal",true);return;}
  try{const d=await api("PUT",`/api/admin/schedule/${id}`,fd("grup_id",grup,"hari",hari||null,"tanggal",tgl||null,"catatan",document.getElementById("ej-cat").value));toast("✅ "+d.message);closeMo("mo-schedule-edit");loadAllSchedules();}
  catch(e){toast(e.message,true);}
}
async function delJadwal(id){
  showConfirm("Hapus Jadwal","Hapus jadwal ini?",async()=>{
    try{const d=await api("DELETE",`/api/admin/schedule/${id}`);toast(d.message);loadAllSchedules();}catch(e){toast(e.message,true);}
  },"Ya, Hapus",true);
}

// ── ADMIN: PENGGANTI (dropdown) ───────────────────────────
let wargaList=[];
async function loadWargaDropdowns(){
  try{
    wargaList=await api("GET","/api/admin/warga/simple");
    const asli=document.getElementById("pg-asli"),pgti=document.getElementById("pg-pgti");
    const opts=`<option value="">Pilih Warga...</option>`+wargaList.map(w=>`<option value="${w.id}">[Grup ${w.grup_id}] ${w.nama} (${w.no_hp})</option>`).join("");
    asli.innerHTML=opts;pgti.innerHTML=opts;toast("Daftar warga dimuat");
  }catch(e){toast(e.message,true);}
}
async function loadPengganti(){
  const b=document.getElementById("pengganti-list");b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const d=await api("GET","/api/admin/pengganti");
    if(!d.length){b.innerHTML=`<p style="color:var(--tx2)">Tidak ada pengganti aktif.</p>`;return;}
    b.innerHTML=d.map(pg=>`<div style="background:var(--bg);border-radius:var(--r2);padding:11px;margin-bottom:7px">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">
        <div style="font-size:.84rem"><b>${pg.tanggal}</b> · Grup ${pg.grup_id}
          <br>${pg.warga_pengganti} menggantikan ${pg.warga_asli}
          ${pg.catatan?`<div style="color:var(--tx2);font-size:.78rem">${pg.catatan}</div>`:""}
        </div>
        <button class="btn btn-xs btn-er" onclick="delPengganti(${pg.id})">🗑</button>
      </div></div>`).join("");
  }catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
async function addPengganti(){
  const tgl=document.getElementById("pg-tgl").value,grup=document.getElementById("pg-grup").value;
  const asliId=document.getElementById("pg-asli").value,pgtiId=document.getElementById("pg-pgti").value;
  if(!tgl||!grup||!asliId||!pgtiId){toast("Isi semua kolom wajib",true);return;}
  try{
    const d=await api("POST","/api/admin/pengganti",fd("tanggal",tgl,"grup_id",grup,"warga_asli_id",asliId,"warga_pengganti_id",pgtiId,"catatan",document.getElementById("pg-cat").value));
    toast("✅ "+d.message);loadPengganti();
  }catch(e){toast(e.message,true);}
}
async function delPengganti(id){
  showConfirm("Hapus Pengganti","Hapus data pengganti ini?",async()=>{
    try{const d=await api("DELETE",`/api/admin/pengganti/${id}`);toast(d.message);loadPengganti();}catch(e){toast(e.message,true);}
  },"Ya, Hapus",true);
}

// ── ADMIN: IMPOR / EKSPOR DATA ───────────────────────────
let dataSetsLoaded=false;
async function loadDataSets(){
  const grid=document.getElementById("dataset-grid");if(!grid||dataSetsLoaded)return;
  try{
    const sets=await api("GET","/api/admin/data/datasets");
    grid.innerHTML=sets.map(s=>`<label class="data-check"><input type="checkbox" class="dataset-cb" value="${s.key}" checked onchange="syncAllDatasets()"><span>${s.label}</span></label>`).join("");
    dataSetsLoaded=true;
  }catch(e){grid.innerHTML=`<p style="color:var(--er);grid-column:1/-1">${e.message}</p>`;}
}
function toggleAllDatasets(checked){document.querySelectorAll(".dataset-cb").forEach(x=>x.checked=checked);}
function syncAllDatasets(){
  const boxes=[...document.querySelectorAll(".dataset-cb")],all=document.getElementById("data-all");
  if(all){all.checked=boxes.length>0&&boxes.every(x=>x.checked);all.indeterminate=boxes.some(x=>x.checked)&&!all.checked;}
}
function selectedDataSets(){
  const boxes=[...document.querySelectorAll(".dataset-cb")],chosen=boxes.filter(x=>x.checked).map(x=>x.value);
  if(!chosen.length)throw new Error("Pilih minimal satu jenis data.");
  return chosen.length===boxes.length?"all":chosen.join(",");
}
function exportData(fmt){
  try{const sets=selectedDataSets(),stamp=new Date().toISOString().slice(0,10);dlToken(`/api/admin/data/export?format=${fmt}&datasets=${encodeURIComponent(sets)}`,`ronda_data_${stamp}.${fmt}`);}
  catch(e){toast(e.message,true);}
}
function downloadWargaTemplate(){dlToken("/api/admin/data/template/warga","template_import_warga.xlsx");}
async function importData(){
  const input=document.getElementById("data-import-file"),file=input.files[0],box=document.getElementById("data-import-result"),btn=document.getElementById("btn-import-data");
  if(!file){toast("Pilih file JSON atau Excel terlebih dahulu.",true);return;}
  let sets;try{sets=selectedDataSets();}catch(e){toast(e.message,true);return;}
  showConfirm("Impor Data",`Impor ${file.name} ke database? Data yang cocok akan diproses sesuai mode pilihan.`,async()=>{
    const form=new FormData();form.append("file",file);form.append("datasets",sets);form.append("mode",document.getElementById("data-import-mode").value);
    btn.classList.add("busy");btn.disabled=true;box.style.display="block";box.textContent="Memproses file...";
    try{
      const d=await api("POST","/api/admin/data/import",form),lines=[`✅ ${d.message} Total ${d.total_rows} baris.`];
      Object.entries(d.summary).forEach(([name,s])=>lines.push(`${name}: ${s.created} baru, ${s.updated} diperbarui, ${s.skipped} dilewati, ${s.failed} gagal`));
      if(d.errors?.length){lines.push("\nKesalahan:");d.errors.forEach(e=>lines.push(`• ${e.dataset} baris ${e.baris}: ${e.error}`));}
      if(d.error_note)lines.push(d.error_note);box.textContent=lines.join("\n");toast("✅ Impor data selesai.",false,5000);loadAdminStats();
    }catch(e){box.textContent="❌ "+e.message;toast(e.message,true,5000);}
    finally{btn.classList.remove("busy");btn.disabled=false;}
  },"Ya, Mulai Impor");
}

// ── LAPORAN ───────────────────────────────────────────────
function expA(){const m=document.getElementById("ex-m").value,s=document.getElementById("ex-s").value;let url="/api/admin/reports/attendance?";if(m)url+=`tgl_mulai=${m}&`;if(s)url+=`tgl_selesai=${s}&`;dlToken(url,"absensi.xlsx");}
function expP(){dlToken("/api/admin/reports/patrol","patroli.xlsx");}
async function dlToken(url,fn){
  try{
    const r=await fetch(url,{headers:{"Authorization":"Bearer "+S.token}});
    if(!r.ok){const d=await r.json().catch(()=>({}));throw new Error(d.detail||`Error ${r.status}`);}
    const b=await r.blob(),obj=URL.createObjectURL(b),a=document.createElement("a");a.href=obj;a.download=fn;document.body.appendChild(a);a.click();document.body.removeChild(a);setTimeout(()=>URL.revokeObjectURL(obj),1000);toast("✅ File berhasil diunduh!");
  }catch(e){toast("Gagal: "+e.message,true);}
}

// ── SOS ADMIN ─────────────────────────────────────────────
async function loadSOS(){
  const b=document.getElementById("soslist");b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const al=await api("GET","/api/admin/emergency");
    if(!al.length){b.innerHTML=`<p style="color:var(--tx2)">Tidak ada alert SOS.</p>`;return;}
    b.innerHTML=al.map(a=>`<div style="background:${a.resolved?"var(--bg)":"rgba(244,63,94,.06)"};border-left:4px solid ${a.resolved?"var(--brd)":"var(--er)"};padding:11px;border-radius:0 var(--r2) var(--r2) 0;margin-bottom:8px">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">
        <div><b>${a.nama}</b> <span style="font-size:.72rem;color:var(--tx2)">${a.waktu}</span>
          <br><span style="font-size:.8rem;color:var(--tx2)">📞 ${a.no_hp} · 📍 ${a.lat?.toFixed(4)}, ${a.lon?.toFixed(4)}</span>
          <br><i style="font-size:.82rem">"${a.keterangan}"</i></div>
        <div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;justify-content:flex-end">
          ${!a.resolved?`<button class="btn btn-xs btn-ok" onclick="resolveAlert(${a.id})">✅ Selesai</button>`:`<span class="badge badge-ok">Tertangani</span>`}
          <button class="btn btn-xs btn-er" onclick="deleteAlert(${a.id})">🗑 Hapus</button>
        </div>
      </div></div>`).join("");
  }catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}
async function resolveAlert(id){try{const d=await api("POST",`/api/admin/emergency/${id}/resolve`,fd());toast(d.message);loadSOS();loadStats();}catch(e){toast(e.message,true);}}
function deleteAlert(id){showConfirm("Hapus Alert SOS","Alert dan notifikasi SOS pada semua akun akan dihapus permanen.",async()=>{try{const d=await api("DELETE",`/api/admin/emergency/${id}`);toast(d.message);loadSOS();loadStats();pollNotifs();}catch(e){toast(e.message,true);}},"Ya, Hapus",true);}

// ── AUDIT LOG ─────────────────────────────────────────────
async function loadAudit(){
  const b=document.getElementById("auditlist");b.innerHTML=`<div class="loading"><div class="spin"></div></div>`;
  try{
    const logs=await api("GET","/api/admin/audit?limit=100");
    b.innerHTML=logs.map(l=>`<div style="font-size:.77rem;padding:7px;background:var(--bg);border-radius:8px;margin-bottom:5px;display:flex;gap:8px;align-items:flex-start">
      <span style="color:var(--tx3);white-space:nowrap;flex-shrink:0">${l.waktu.slice(11,19)}</span>
      <div><b>${l.nama}</b> <span style="color:var(--p);font-weight:700">${l.action}</span>${l.detail?`<br><span style="color:var(--tx2)">${l.detail}</span>`:""}</div>
    </div>`).join("")||`<p style="color:var(--tx2)">Tidak ada log.</p>`;
  }catch(e){b.innerHTML=`<p style="color:var(--er)">${e.message}</p>`;}
}

// ── SERVICE WORKER ────────────────────────────────────────
if("serviceWorker" in navigator){
  navigator.serviceWorker.register("/static/sw.js").then(r=>r.update()).catch(()=>{});
  navigator.serviceWorker.addEventListener("message",event=>{if(event.data?.type==="PUSH_OPEN")handlePushTarget(event.data.target);});
}

// ── START ─────────────────────────────────────────────────
init();
</script>
</body>
</html>

SKHTMLEOF
info "index.html v6.10.0 siap"

section "MIGRASI DATABASE (aman — hanya tambah yang kurang)"
python3 - "$APP_DIR" << 'MIGEOF'
import sys, sqlite3, re
from pathlib import Path
from datetime import datetime, date

APP = Path(sys.argv[1]); DB = APP / "ronda.db"
NOW = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f"); n = 0

if not DB.exists():
    print("  Database belum ada — dibuat saat server start pertama kali.")
    sys.exit(0)

print(f"  Database: {DB}")
conn = sqlite3.connect(str(DB)); conn.row_factory = sqlite3.Row; cur = conn.cursor()

def has_col(t,c):
    cur.execute(f"PRAGMA table_info({t})")
    return any(r["name"]==c for r in cur.fetchall())
def has_tbl(t):
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?",(t,))
    return bool(cur.fetchone())
def add_col(t,c,typ="TEXT",default=None):
    global n
    if not has_col(t,c):
        cur.execute(f"ALTER TABLE {t} ADD COLUMN {c} {typ}")
        if default is not None: cur.execute(f"UPDATE {t} SET {c}=? WHERE {c} IS NULL",(default,))
        print(f"  [+] {t}.{c}"); n+=1
def make_tbl(name,cols):
    global n
    if not has_tbl(name):
        cur.execute(f"CREATE TABLE {name} ({cols})")
        print(f"  [+] tabel {name}"); n+=1

if has_tbl("settings"):
    if has_col("settings","keterangan") and not has_col("settings","label"):
        cur.execute("ALTER TABLE settings ADD COLUMN label TEXT")
        cur.execute("UPDATE settings SET label=keterangan")
        print("  [+] settings.label"); n+=1
    else: add_col("settings","label")
    add_col("settings","updated_at",default=NOW)
if has_tbl("warga"):
    add_col("warga","akun_id"); add_col("warga","password_hash"); add_col("warga","auth_version","INTEGER",1)
    add_col("warga","catatan"); add_col("warga","created_at",default=NOW)
    prefixes={"super_admin":"SA","admin":"AD","koordinator":"KR","warga":"WG"}
    rows=cur.execute("SELECT id,role,no_hp,nama,akun_id,is_active,created_at FROM warga ORDER BY CASE WHEN role='super_admin' AND (no_hp='0000' OR nama='Super Admin') THEN 0 ELSE 1 END, CASE WHEN is_active=1 THEN 0 ELSE 1 END, COALESCE(created_at,''), id").fetchall()
    used={p:set() for p in prefixes.values()}
    for row in rows:
        role=row["role"] if row["role"] in prefixes else "warga"; prefix=prefixes[role]
        raw=(row["akun_id"] or "").strip(); aid=raw.upper()
        if raw==aid and re.fullmatch(prefix+r"\d{5}",aid): used[prefix].add(int(aid[-5:]))
    for row in rows:
        raw=(row["akun_id"] or "").strip(); aid=raw.upper()
        if not aid: continue
        role=row["role"] if row["role"] in prefixes else "warga"; prefix=prefixes[role]
        if raw==aid and re.fullmatch(prefix+r"\d{5}",aid): continue
        seq=1
        while seq in used[prefix]: seq+=1
        new_id=f"{prefix}{seq:05d}"; used[prefix].add(seq)
        cur.execute("UPDATE warga SET akun_id=? WHERE id=?",(new_id,row["id"])); n+=1
        print(f"  [~] warga.id {row['id']}: {aid} -> {new_id}")
    cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_warga_akun_id ON warga(akun_id)")
    cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS ux_warga_akun_id_nocase ON warga(akun_id COLLATE NOCASE)")
if has_tbl("checkpoints"):
    add_col("checkpoints","lat","REAL"); add_col("checkpoints","lon","REAL")
    add_col("checkpoints","urutan","INTEGER",0)
    add_col("checkpoints","radius_meter","INTEGER",30)
    cur.execute("UPDATE checkpoints SET radius_meter=30 WHERE radius_meter IS NULL OR radius_meter IN (100,300)")
    add_col("checkpoints","created_at",default=NOW)
    patrol_rows=cur.execute("SELECT id,urutan FROM checkpoints WHERE tipe='patrol' ORDER BY CASE WHEN COALESCE(urutan,0)>0 THEN urutan ELSE 999999 END,id").fetchall()
    for order,row in enumerate(patrol_rows,1):
        if row["urutan"]!=order: cur.execute("UPDATE checkpoints SET urutan=? WHERE id=?",(order,row["id"])); n+=1
if has_tbl("chat_messages"):
    add_col("chat_messages","reply_to_id","INTEGER")
    add_col("chat_messages","is_deleted","INTEGER",0)
    add_col("chat_messages","media_paths")
if has_tbl("patrol_visits"):
    add_col("patrol_visits","photo_paths")
if has_tbl("attendance"):
    add_col("attendance","status","TEXT","hadir")
    add_col("attendance","keterangan","TEXT")
    add_col("attendance","manual_by","INTEGER")

make_tbl("audit_log","id INTEGER PRIMARY KEY,warga_id INTEGER,action TEXT,detail TEXT,ip TEXT,ts TEXT DEFAULT CURRENT_TIMESTAMP")
make_tbl("emergency","id INTEGER PRIMARY KEY,warga_id INTEGER,lat REAL,lon REAL,ket TEXT,ts TEXT DEFAULT CURRENT_TIMESTAMP,resolved INTEGER DEFAULT 0,resolved_by INTEGER")
make_tbl("iuran","id INTEGER PRIMARY KEY,warga_id INTEGER,bulan INTEGER,tahun INTEGER,nominal INTEGER DEFAULT 0,tgl_bayar TEXT,bukti_path TEXT,catatan TEXT,status TEXT DEFAULT 'belum'")
make_tbl("kompensasi","id INTEGER PRIMARY KEY,warga_id INTEGER,grup_id INTEGER,jadwal_id INTEGER,tanggal TEXT,hari TEXT,nominal INTEGER DEFAULT 25000,alasan TEXT,status TEXT DEFAULT 'belum',verified_by INTEGER,verified_at TEXT,catatan TEXT,created_at TEXT DEFAULT CURRENT_TIMESTAMP")
make_tbl("devices","id INTEGER PRIMARY KEY,warga_id INTEGER,installation_id TEXT,last_seen TEXT")
make_tbl("jadwal_ronda","id INTEGER PRIMARY KEY,grup_id INTEGER,hari INTEGER,tanggal TEXT,catatan TEXT,is_active INTEGER DEFAULT 1")
make_tbl("pengganti_ronda","id INTEGER PRIMARY KEY,tanggal TEXT,warga_asli_id INTEGER,warga_pengganti_id INTEGER,grup_id INTEGER,catatan TEXT,disetujui_oleh INTEGER,created_at TEXT DEFAULT CURRENT_TIMESTAMP")
make_tbl("chat_messages","id INTEGER PRIMARY KEY,grup_id INTEGER,warga_id INTEGER,tipe TEXT DEFAULT 'text',pesan TEXT,timestamp TEXT DEFAULT CURRENT_TIMESTAMP,reply_to_id INTEGER,reply_preview TEXT,is_deleted INTEGER DEFAULT 0,media_paths TEXT")
make_tbl("chat_invites","id INTEGER PRIMARY KEY,grup_id INTEGER,dari_id INTEGER,ke_id INTEGER,status TEXT DEFAULT 'pending',timestamp TEXT DEFAULT CURRENT_TIMESTAMP")
make_tbl("notifikasi","id INTEGER PRIMARY KEY,grup_id INTEGER,warga_id INTEGER,tipe TEXT,judul TEXT,pesan TEXT,dibaca INTEGER DEFAULT 0,timestamp TEXT DEFAULT CURRENT_TIMESTAMP")
make_tbl("push_subscriptions","id INTEGER PRIMARY KEY,warga_id INTEGER NOT NULL,endpoint TEXT UNIQUE NOT NULL,p256dh TEXT NOT NULL,auth TEXT NOT NULL,user_agent TEXT,created_at TEXT DEFAULT CURRENT_TIMESTAMP,last_seen TEXT DEFAULT CURRENT_TIMESTAMP")
make_tbl("group_info","id INTEGER PRIMARY KEY,grup_id INTEGER UNIQUE,nama TEXT,deskripsi TEXT,updated_at TEXT")
if has_tbl("kompensasi"):
    cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_kompensasi_warga_tanggal ON kompensasi(warga_id,tanggal)")
    cur.execute("CREATE INDEX IF NOT EXISTS ix_kompensasi_status ON kompensasi(status)")
if has_tbl("notifikasi"):
    add_col("notifikasi","source_id","INTEGER")
    cur.execute("CREATE INDEX IF NOT EXISTS ix_notifikasi_source_id ON notifikasi(source_id)")
if has_tbl("push_subscriptions"):
    cur.execute("CREATE INDEX IF NOT EXISTS ix_push_subscriptions_warga_id ON push_subscriptions(warga_id)")

DEFS=[
    ("jam_mulai","23:00","Jam Mulai Ronda"),("jam_selesai","04:00","Jam Selesai Ronda"),
    ("nama_kampung","Siskamling RT/RW","Nama Lingkungan"),("nominal_iuran","50000","Iuran Bulanan (Rp)"),
    ("kompensasi_aktif","true","Aktifkan Tagihan Kompensasi"),
    ("nominal_kompensasi","25000","Nominal Kompensasi Tidak Ronda (Rp)"),
    ("kompensasi_mulai",date.today().isoformat(),"Mulai Perhitungan Kompensasi"),
    ("patrol_wajib_berurutan","true","Wajib Patroli Sesuai Urutan Checkpoint"),
    ("radius_checkpoint_meter","30","Radius Default Checkpoint Patroli (meter)"),
    ("retensi_foto_hari","7","Retensi Foto Patroli di Server"),
    ("allow_bypass_time","false","Izinkan Absen di Luar Jam"),("jadwal_wajib","true","Wajib Sesuai Jadwal Grup"),
    ("max_grup","6","Jumlah Grup Ronda"),("koordinat_lat","-6.2088","Koordinat Pusat Lat"),
    ("koordinat_lon","106.8456","Koordinat Pusat Lon"),("versi","6.10.0","Versi Aplikasi"),
]
existing=set()
if has_tbl("settings"): existing={r[0] for r in cur.execute("SELECT key FROM settings").fetchall()}
for k,v,l in DEFS:
    if k not in existing:
        cur.execute("INSERT INTO settings(key,value,label,updated_at) VALUES(?,?,?,?)",(k,v,l,NOW))
        print(f"  [+] setting '{k}'"); n+=1
    else:
        cur.execute("UPDATE settings SET label=? WHERE key=? AND (label IS NULL OR label='')",(l,k))
cur.execute("UPDATE settings SET value='30', updated_at=? WHERE key='radius_checkpoint_meter' AND value IN ('100','300','')",(NOW,))
cur.execute("UPDATE settings SET value='6.10.0', updated_at=? WHERE key='versi'",(NOW,))

if has_tbl("checkpoints") and cur.execute("SELECT COUNT(*) FROM checkpoints").fetchone()[0]==0:
    CPS=[("Pos Masuk Utama","QR-IN","Pintu Masuk RT","checkin",None,None,0,30),
         ("Pos Keluar Utama","QR-OUT","Pintu Keluar RT","checkout",None,None,0,30),
         ("Patroli Pos Alpha","POS-A","Pojok Utara","patrol",-6.2080,106.8450,1,30),
         ("Patroli Pos Bravo","POS-B","Pojok Selatan","patrol",-6.2100,106.8470,2,30),
         ("Patroli Pos Charlie","POS-C","Jalan Tengah","patrol",-6.2090,106.8460,3,30),
         ("Patroli Pos Delta","POS-D","Ujung Barat","patrol",-6.2070,106.8440,4,30)]
    for nm,tok,lok,tip,lat,lon,order,radius in CPS:
        cur.execute("INSERT INTO checkpoints(nama,token,lokasi,tipe,is_active,lat,lon,urutan,radius_meter,created_at) VALUES(?,?,?,?,1,?,?,?,?,?)",(nm,tok,lok,tip,lat,lon,order,radius,NOW))
    print("  [+] checkpoint default"); n+=1

if has_tbl("warga") and cur.execute("SELECT COUNT(*) FROM warga").fetchone()[0]==0:
    cur.execute("INSERT INTO warga(nama,akun_id,no_hp,tanggal_lahir,grup_id,role,is_active,created_at) VALUES('Super Admin','SA00001','0000','01-01-2000',0,'super_admin',1,?)",(NOW,))
    print("  [+] super admin default"); n+=1

cur.execute("PRAGMA integrity_check"); ic=cur.fetchone()[0]; print(f"  Integrity: {ic}")
conn.commit(); conn.close()
print(f"\n  Migrasi selesai: {n} perubahan diterapkan.")
MIGEOF
info "Migrasi database selesai"


section "INSTALL DEPENDENCIES"
python3 -m venv "$SCRIPT_DIR/venv"
source "$SCRIPT_DIR/venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet -r "$APP_DIR/requirements.txt"
info "Dependencies terinstall"

section "KONFIGURASI WEB PUSH"
"$SCRIPT_DIR/venv/bin/python" - "$APP_DIR/vapid_private.pem" "$SCRIPT_DIR/.env" <<'PY'
import base64,sys
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
key_path,env_path=Path(sys.argv[1]),Path(sys.argv[2])
if key_path.exists():
    private=serialization.load_pem_private_key(key_path.read_bytes(),password=None)
else:
    private=ec.generate_private_key(ec.SECP256R1())
    key_path.write_bytes(private.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.TraditionalOpenSSL,serialization.NoEncryption()))
public=private.public_key().public_bytes(serialization.Encoding.X962,serialization.PublicFormat.UncompressedPoint)
public_key=base64.urlsafe_b64encode(public).decode().rstrip("=")
lines=env_path.read_text().splitlines() if env_path.exists() else []
current={line.split("=",1)[0].strip():line.split("=",1)[1].strip() for line in lines if "=" in line and not line.lstrip().startswith("#")}
values={"VAPID_PUBLIC_KEY":public_key,
        "VAPID_SUBJECT":current.get("VAPID_SUBJECT") or "mailto:admin@ronda.lavi.web.id",
        "APP_TIMEZONE":current.get("APP_TIMEZONE") or "Asia/Jakarta"}
seen=set(); output=[]
for line in lines:
    name=line.split("=",1)[0].strip() if "=" in line and not line.lstrip().startswith("#") else ""
    if name in values: output.append(f"{name}={values[name]}"); seen.add(name)
    else: output.append(line)
for name,value in values.items():
    if name not in seen: output.append(f"{name}={value}")
env_path.write_text("\n".join(output)+"\n")
PY
chmod 600 "$APP_DIR/vapid_private.pem" "$SCRIPT_DIR/.env"
source "$SCRIPT_DIR/.env" 2>/dev/null || true
info "Kunci Web Push siap dan dipertahankan untuk upgrade berikutnya"

section "JALANKAN SERVER"
cd "$APP_DIR"
SQLITE_WEB_PASSWORD="$DB_WEB_PASSWORD" "$SCRIPT_DIR/venv/bin/sqlite_web" \
  --port "$DB_PORT" --host "$DB_WEB_HOST" --no-browser --password \
  "$APP_DIR/ronda.db" \
  > "$SCRIPT_DIR/logs/sqlite_web.log" 2>&1 &
DBWEB_PID=$!; echo "$DBWEB_PID" > "$SCRIPT_DIR/.pid_dbweb"

SK=$SK PORT=$PORT DB_PORT=$DB_PORT VAPID_PUBLIC_KEY="$VAPID_PUBLIC_KEY" \
VAPID_PRIVATE_KEY_PATH="$APP_DIR/vapid_private.pem" VAPID_SUBJECT="$VAPID_SUBJECT" APP_TIMEZONE="$APP_TIMEZONE" \
  "$SCRIPT_DIR/venv/bin/uvicorn" main:app \
  --host "$APP_HOST" --port "$PORT" \
  --workers 1 --access-log \
  > "$SCRIPT_DIR/logs/server.log" 2>&1 &
APP_PID=$!; echo "$APP_PID" > "$SCRIPT_DIR/.pid_app"
cd "$SCRIPT_DIR"

echo -n "  Menunggu server siap"
for i in $(seq 1 20); do
  sleep 1; echo -n "."
  python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PORT/health',timeout=2)" 2>/dev/null && break || true
done; echo ""

if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo -e "${RED}Server gagal! Cek: tail -20 logs/server.log${NC}"; tail -15 "$SCRIPT_DIR/logs/server.log"; exit 1
fi
info "Server berjalan (PID: $APP_PID)"
if kill -0 "$DBWEB_PID" 2>/dev/null && python3 - "$DB_PORT" <<'PY'
import socket,sys
s=socket.socket(); s.settimeout(2)
ok=s.connect_ex(("127.0.0.1",int(sys.argv[1])))==0
s.close(); raise SystemExit(0 if ok else 1)
PY
then
  info "SQLite Web berjalan di port $DB_PORT (PID: $DBWEB_PID)"
else
  warn "SQLite Web belum merespons. Cek: tail -30 logs/sqlite_web.log"
fi

section "CRON BACKUP"
CRON="0 2 * * * $SCRIPT_DIR/backup.sh >> $SCRIPT_DIR/logs/backup.log 2>&1"
if command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null|grep -v "backup.sh";echo "$CRON")|crontab - 2>/dev/null && info "Cron backup jam 02:00 OK" || warn "Daftarkan manual: crontab -e"
else
  warn "crontab tidak tersedia. Jalankan backup.sh manual atau install cron/cronie."
fi

LOCAL_IP=$(hostname -I 2>/dev/null|awk '{print $1}'||echo "127.0.0.1")
MODE_STR=$([ "$IS_UP" = "true" ] && echo "UPGRADE v6.10.0 BERHASIL" || echo "INSTALASI v6.10.0 BERHASIL")

echo -e "${GRN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
printf "  ║  ✅  %-56s ║\n" "$MODE_STR"
echo "  ╠══════════════════════════════════════════════════════════════╣"
printf "  ║  %-60s ║\n" "📱 Aplikasi  : http://$LOCAL_IP:$PORT"
printf "  ║  %-60s ║\n" "🗄️  Database  : http://$DB_WEB_HOST:$DB_PORT"
printf "  ║  %-60s ║\n" "☁️  Cloudflare: https://$DB_PUBLIC_HOST"
printf "  ║  %-60s ║\n" "📖 API Docs  : http://$LOCAL_IP:$PORT/api/docs"
echo "  ╠══════════════════════════════════════════════════════════════╣"
printf "  ║  %-60s ║\n" "🔑 Super Admin: $DEFAULT_ADMIN_ID | Password: $DEFAULT_ADMIN_PASSWORD"
printf "  ║  %-60s ║\n" "🗄️  SQLite Web password: $DB_WEB_PASSWORD"
echo "  ║  ⚠️  Simpan kredensial lalu segera ganti password admin.    ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo "  ║  📄 tail -f logs/server.log   🔄 bash siskamling.sh        ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${YLW}Cloudflare Tunnel:${NC} arahkan ${BOLD}$DB_PUBLIC_HOST${NC} ke ${BOLD}http://127.0.0.1:$DB_PORT${NC} (HTTP, bukan HTTPS)."
echo -e "${YLW}Jangan gunakan db.ronda.lavi.web.id${NC} tanpa sertifikat khusus multi-level. Gunakan hostname satu tingkat seperti $DB_PUBLIC_HOST."
