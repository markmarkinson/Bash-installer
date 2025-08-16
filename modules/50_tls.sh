#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/00_common.sh"
require_root

apt_install certbot python3-certbot-nginx

read -rp "E-Mail für Let's Encrypt (Pflicht): " LE_MAIL
[ -n "$LE_MAIL" ] || { err "E-Mail ist erforderlich."; exit 1; }

read -rp "Domains (mit Leerzeichen getrennt, z.B. example.com www.example.com): " DOMS
[ -n "$DOMS" ] || { err "Mindestens eine Domain angeben."; exit 1; }

read -rp "Staging (Test-Modus) benutzen? (y/n): " LE_STAGING
read -rp "HSTS aktivieren (Strict-Transport-Security)? (y/n): " LE_HSTS

for D in $DOMS; do
  if ! grep -Rqs "server_name[[:space:]]\+${D}\b" /etc/nginx/sites-available /etc/nginx/sites-enabled 2>/dev/null; then
    log "Erzeuge minimalen HTTP-ServerBlock für ${D}…"
    ROOT="/var/www/${D}/_placeholder"
    install -d -m 755 "$ROOT"
    CFG="/etc/nginx/sites-available/${D}.conf"
    cat > "$CFG" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${D};
    root ${ROOT};
    location / { return 200 "ACME ready for ${D}\n"; }
}
NGINX
    ln -sf "$CFG" "/etc/nginx/sites-enabled/$(basename "$CFG")"
  fi
done

nginx -t && (systemctl reload nginx || systemctl restart nginx)

args=(--nginx -n --agree-tos -m "$LE_MAIL" --redirect --no-eff-email)
[[ "$LE_STAGING" =~ ^[yY]$ ]] && args+=(--staging)
for D in $DOMS; do args+=(-d "$D"); done

certbot "${args[@]}"

if [[ "$LE_HSTS" =~ ^[yY]$ ]]; then
  for D in $DOMS; do
    CAND="/etc/nginx/sites-available/${D}.conf"
    [ -f "$CAND" ] || continue
    if ! grep -q 'Strict-Transport-Security' "$CAND"; then
      sed -i -E "0,/server_name[[:space:]]+${D};/ s//&\n    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;/" "$CAND"
    fi
  done
fi

nginx -t && (systemctl reload nginx || systemctl restart nginx)

systemctl enable --now certbot.timer 2>/dev/null || true

log "Let's Encrypt fertig für: ${DOMS}"
