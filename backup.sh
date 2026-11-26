#!/usr/bin/env bash
# نسخة احتياطية لقاعدة البيانات. الاستخدام: DATABASE_URL="postgresql://..." bash scripts/backup.sh
# لا تشمل ملفات Storage (الصور): انسخها من لوحة Supabase أو عبر Storage API.
set -euo pipefail
: "${DATABASE_URL:?set DATABASE_URL}"
mkdir -p backups && chmod 700 backups
OUT="backups/mohimtak-$(date +%Y%m%d-%H%M%S).dump"
umask 077
pg_dump "$DATABASE_URL" --format=custom --no-owner --schema=public --schema=auth --schema=storage --file="$OUT"
pg_restore --list "$OUT" >/dev/null
echo "saved $OUT"
