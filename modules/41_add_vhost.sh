#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/00_common.sh"
require_root

PHP_SOCK="$(detect_php_sock || true)"
[ -n "$PHP_SOCK" ] || PHP_SOCK="/run/php/php-fpm.sock"

read -rp "Domain (z.B. example.com): " DOMAIN
[ -n "$DOMAIN" ] || { err "Domain erforderlich."; exit 1; }

read -rp "URL-Prefix (z.B. /app, /api): " PREFIX
PREFIX="$(norm_prefix "$PREFIX")"
[ "$PREFIX" = "/" ] && { err "Bitte keinen reinen '/'-Prefix."; exit 1; }

read -rp "HTTP Basic Auth aktivieren? (y/n): " AUTH

ROOT_DIR="/var/www/${DOMAIN}${PREFIX}/public"
create_sample_content "$ROOT_DIR" "$PREFIX"

AUTH_BLOCK=""; CREDS_NOTE=""
if [[ "$AUTH" =~ ^[yY]$ ]]; then
  AUTH_USER="admin"; AUTH_PASS="$(gen_pw 24)"
  SLUG_DOM="$(slugify "$DOMAIN")"; SLUG_PRE="$(slugify "$PREFIX")"
  AUTH_FILE="/etc/nginx/.htpasswd_${SLUG_DOM}_${SLUG_PRE}"
  install -d -m 750 -o root -g www-data /etc/nginx
  htpasswd -bBc "$AUTH_FILE" "$AUTH_USER" "$AUTH_PASS" >/dev/null
  chmod 640 "$AUTH_FILE"; chown root:www-data "$AUTH_FILE"
  AUTH_BLOCK="auth_basic \"Restricted\";\n        auth_basic_user_file ${AUTH_FILE};"
  printf "%s\n" "VHOST ${DOMAIN}${PREFIX} BASIC_AUTH_USER=${AUTH_USER} BASIC_AUTH_PASS=${AUTH_PASS} HTPASSWD=${AUTH_FILE}" >> /root/credentials.txt
  CREDS_NOTE=" (BasicAuth aktiviert)"
fi

CFG="/etc/nginx/sites-available/${DOMAIN}.conf"
cat > "$CFG" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log warn;

    location = / { return 301 ${PREFIX}/; }

    location ${PREFIX}/ {
        ${AUTH_BLOCK}
        alias ${ROOT_DIR}/;
        index index.php index.html;
        try_files $uri $uri/ ${PREFIX}/index.php?$query_string;
    }

    location ~ ^${PREFIX}/(.+\.php)$ {
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME ${ROOT_DIR}/$1;
        fastcgi_pass unix:${PHP_SOCK};
    }
}
NGINX
ln -sf "$CFG" "/etc/nginx/sites-enabled/$(basename "$CFG")"

nginx -t && (systemctl reload nginx || systemctl restart nginx) || { err "nginx reload fehlgeschlagen"; exit 1; }
log "vHost erstellt: http://${DOMAIN}${PREFIX}/ ${CREDS_NOTE}"
