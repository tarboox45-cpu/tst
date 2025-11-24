#!/usr/bin/env bash
# Pterodactyl Theme Build Script (Node 20 + Webpack 4 compatibility)
# Usage: sudo /usr/local/bin/ptero-theme-build.sh [-d /var/www/pterodactyl] [--no-migrate]

set -Eeuo pipefail

### ---------- Config ----------
PANEL_DIR="/var/www/pterodactyl"
RUN_MIGRATIONS="yes"
### ----------------------------

log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*"; }
die() { err "$*"; exit 1; }

usage() {
  cat <<EOF
Pterodactyl Theme Build Script

Options:
  -d, --dir <path>   مسار مجلد لوحة Pterodactyl (افتراضي: /var/www/pterodactyl)
      --no-migrate   تخطي php artisan migrate
  -h, --help         عرض هذه المساعدة
EOF
}

# --- Args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir) PANEL_DIR="${2:-}"; shift 2 ;;
    --no-migrate) RUN_MIGRATIONS="no"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "خيار غير معروف: $1"; usage; exit 1 ;;
  esac
done

# --- Preconditions ---
[[ $EUID -eq 0 ]] || die "شغّل السكربت بصلاحيات الروت."
[[ -d "$PANEL_DIR" ]] || die "المجلد غير موجود: $PANEL_DIR"
cd "$PANEL_DIR"

[[ -f package.json ]] || die "لم أجد package.json داخل $PANEL_DIR — تأكد أنك في مجلد لوحة Pterodactyl الصحيح."

command -v php >/dev/null 2>&1 || die "PHP غير مثبت."
command -v curl >/dev/null 2>&1 || die "curl غير مثبت. ثبّته عبر: apt install -y curl"

# --- Ensure Node.js 20 (recommended) ---
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
else
  NODE_MAJOR=0
fi

if [[ "$NODE_MAJOR" -lt 18 ]]; then
  log "تثبيت Node.js 20 (LTS)..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
else
  log "Node.js موجود (v$(node -v)); عدم الحاجة لإعادة تثبيته."
fi

# --- Ensure Yarn ---
if ! command -v yarn >/dev/null 2>&1; then
  log "تثبيت Yarn عالميًا..."
  npm i -g yarn
else
  log "Yarn موجود (v$(yarn -v))."
fi

# --- Backup public/assets (optional) ---
ASSETS_DIR="$PANEL_DIR/public/assets"
if [[ -d "$ASSETS_DIR" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  BKP="/root/ptero-assets-backup-$TS.tar.gz"
  log "أخذ نسخة احتياطية للأصول: $BKP"
  tar -czf "$BKP" -C "$ASSETS_DIR" .
fi

# --- Install deps ---
log "تثبيت تبعيات الواجهة عبر Yarn..."
yarn install --frozen-lockfile || yarn install

# --- Ensure react-feather is present (idempotent) ---
if ! grep -q '"react-feather"' package.json 2>/dev/null; then
  log "إضافة react-feather..."
  yarn add react-feather --silent
else
  log "react-feather موجود بالفعل."
fi

# --- Optional: update browserslist DB to silence warnings ---
log "تحديث قاعدة caniuse-lite (browserslist)..."
npx update-browserslist-db@latest --yes || true

# --- Laravel migrations (non-interactive) ---
if [[ "$RUN_MIGRATIONS" == "yes" ]]; then
  if [[ -f artisan ]]; then
    log "تشغيل ترحيلات Laravel (بدون تفاعل)..."
    php artisan migrate --force || warn "لا شيء للمهاجرة أو حدث تحذير."
  else
    warn "ملف artisan غير موجود — تخطي المايجريشن."
  fi
else
  warn "تم تخطي المايجريشن بطلبك (--no-migrate)."
fi

# --- Clean old assets (like original script) ---
if [[ -d "$ASSETS_DIR" ]]; then
  log "تنظيف ملفات JS و sourcemaps القديمة..."
  find "$ASSETS_DIR" \( -name "*.js" -o -name "*.map" \) -type f -delete || true
fi

# --- Build for production with OpenSSL legacy fix (Webpack 4 + Node 20) ---
log "بدء عملية البناء للإنتاج..."
export NODE_OPTIONS="--openssl-legacy-provider"
yarn build:production
unset NODE_OPTIONS

# --- Clear Laravel view cache (+ extra caches safely) ---
if [[ -f artisan ]]; then
  log "تنظيف كاش العرض والتكوين والمسارات..."
  php artisan view:clear || true
  php artisan config:clear || true
  php artisan route:clear || true
  php artisan cache:clear || true
fi

log "اكتمل التثبيت/البناء بنجاح ✅"
echo
echo "المجلد: $PANEL_DIR"
echo "إذا واجهت تحذيرات peerDependency من Yarn فهي معلوماتية غالبًا ولا تمنع البناء."
