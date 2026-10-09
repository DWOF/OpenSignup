#!/usr/bin/env bash
# Nightly database backup. Keeps 14 days in /opt/signup-backups.
# Install with:  sudo crontab -e   then add
#   15 2 * * * /opt/OpenSignup/easebourne/backup.sh >> /var/log/signup-backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=/opt/signup-backups
mkdir -p "$DEST"
chmod 700 "$DEST"
STAMP=$(date +%Y-%m-%d_%H%M)
docker compose -f docker-compose.prod.yml exec -T db \
  pg_dump -U signup -d signup --format=custom > "$DEST/signup-$STAMP.dump"
find "$DEST" -name 'signup-*.dump' -mtime +14 -delete
echo "$(date -Is) backup ok: signup-$STAMP.dump"
