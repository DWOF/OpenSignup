#!/usr/bin/env bash
# One-command setup for the Easebourne sign-up server (Ubuntu 24.04, Lightsail).
#
# Run on the server:
#   curl -fsSL https://raw.githubusercontent.com/DWOF/opensignup/main/easebourne/setup.sh | sudo bash
#
# It installs Docker, adds swap, clones the fork, asks a few questions,
# writes the settings file, builds and starts everything, and sets up
# nightly backups. Safe to run again: it keeps an existing settings file
# unless you choose to replace it.
set -euo pipefail

REPO_URL="https://github.com/DWOF/opensignup.git"
DIR="${DIR:-/opt/OpenSignup}"
DRYRUN="${DRYRUN:-0}"   # DRYRUN=1: only write the settings file (for testing)

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask()  { local p="$1" d="${2:-}" v; read -r -p "$p${d:+ [$d]}: " v </dev/tty; printf '%s' "${v:-$d}"; }
secret() {
  local p="$1" a b
  while :; do
    read -r -s -p "$p: " a </dev/tty; echo >/dev/tty
    read -r -s -p "Again: " b </dev/tty; echo >/dev/tty
    [ -n "$a" ] && [ "$a" = "$b" ] && { printf '%s' "$a"; return; }
    echo "They didn't match, or were empty. Try again." >/dev/tty
  done
}

if [ "$DRYRUN" != 1 ]; then
  [ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }

  say "1/6 Docker"
  if ! command -v docker >/dev/null; then
    curl -fsSL https://get.docker.com | sh
  fi
  usermod -aG docker ubuntu 2>/dev/null || true

  say "2/6 Swap and security updates"
  if ! swapon --show | grep -q /swapfile; then
    fallocate -l 2G /swapfile && chmod 600 /swapfile
    mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades >/dev/null

  say "3/6 Code"
  if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull --ff-only
  else
    git clone "$REPO_URL" "$DIR"
  fi
fi
cd "$DIR"

say "4/6 Settings"
write_env=1
if [ -f .env ]; then
  [ "$(ask 'A settings file already exists. Replace it? (y/N)' N)" = y ] || write_env=0
fi

if [ "$write_env" = 1 ]; then
  echo "Press Enter to accept the value in [brackets]."
  DOMAIN=$(ask "Web address" "signup.1steasebournescoutsandguides.com")
  FROM=$(ask "Sending mailbox" "signup@1steasebournescoutsandguides.com")
  SMTP_HOST=$(ask "SMTP server" "smtp.dreamhost.com")
  SMTP_PORT=$(ask "SMTP port" "587")
  SMTP_PASS=$(secret "Password for $FROM")
  while [[ "$SMTP_PASS" == *"'"* ]]; do
    echo "That password contains a ' which the settings file can't hold. Change it in DreamHost, then enter the new one." >/dev/tty
    SMTP_PASS=$(secret "Password for $FROM")
  done
  SUPPORT=$(ask "Contact email shown to parents" "gsl@easebournescouts.org.uk")
  OPERATOR=$(ask "Data controller name" "1st Easebourne Scout Group")
  GATE_USER=$(ask "Leaders' username" "leaders")
  GATE_PASS=$(secret "Leaders' password (min 12 characters)")
  while [ "${#GATE_PASS}" -lt 12 ]; do GATE_PASS=$(secret "Too short. Leaders' password"); done

  if [ "$DRYRUN" = 1 ]; then
    GATE_HASH="${TEST_HASH:?}"
  else
    GATE_HASH=$(docker run --rm caddy:2-alpine caddy hash-password --plaintext "$GATE_PASS")
  fi

  umask 077
  cat > .env <<EOF
AUTH_SECRET=$(openssl rand -hex 32)
AUTH_URL=https://$DOMAIN
NEXT_PUBLIC_APP_URL=https://$DOMAIN
POSTGRES_PASSWORD=$(openssl rand -hex 24)

EMAIL_TRANSPORT=smtp
EMAIL_FROM="Easebourne Scouts & Guides <$FROM>"
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USER=$FROM
SMTP_PASSWORD='$SMTP_PASS'

NEXT_PUBLIC_INSTANCE_NAME="Easebourne Scouts & Guides"
NEXT_PUBLIC_SUPPORT_EMAIL=$SUPPORT
NEXT_PUBLIC_SOURCE_URL=https://github.com/DWOF/opensignup
NEXT_PUBLIC_GOVERNING_LAW="England and Wales"
NEXT_PUBLIC_OPERATOR_NAME="$OPERATOR"

SITE_ADDRESS=$DOMAIN
GATE_USER=$GATE_USER
GATE_HASH='$GATE_HASH'
EOF
  chmod 600 .env
  unset SMTP_PASS GATE_PASS
  echo "Settings written to $DIR/.env (readable by root only)."
fi

[ "$DRYRUN" = 1 ] && exit 0

DOMAIN=$(grep '^SITE_ADDRESS=' .env | cut -d= -f2)
MYIP=$(curl -fsS https://checkip.amazonaws.com || true)
DNSIP=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')
if [ "$DNSIP" != "$MYIP" ]; then
  say "Warning: $DOMAIN points to '${DNSIP:-nothing yet}', this server is $MYIP."
  echo "The HTTPS certificate needs the DNS record first. Wait for it, then run this script again."
  [ "$(ask 'Build and start anyway? (y/N)' N)" = y ] || exit 0
fi

say "5/6 Build and start (5 to 10 minutes)"
./easebourne/apply.sh
docker compose -f docker-compose.prod.yml -f easebourne/docker-compose.caddy.yml up -d --build

say "6/6 Backups"
chmod +x easebourne/backup.sh
( crontab -l 2>/dev/null | grep -v signup-backup; \
  echo "15 2 * * * $DIR/easebourne/backup.sh >> /var/log/signup-backup.log 2>&1" ) | crontab -

say "Checking it is up"
for i in $(seq 1 30); do
  if curl -fsS "https://$DOMAIN/api/public/health" 2>/dev/null; then
    echo; say "Done. Sign in at https://$DOMAIN/login"
    exit 0
  fi
  sleep 10
done
echo "Not answering yet. Check with:"
echo "  cd $DIR && docker compose -f docker-compose.prod.yml -f easebourne/docker-compose.caddy.yml logs --tail 50"
