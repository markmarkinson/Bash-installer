#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/00_common.sh"
require_root

PHP_SOCK="$(detect_php_sock || true)"
[ -n "$PHP_SOCK" ] || PHP_SOCK="/run/php/php-fpm.sock"

add_vhost() {
  local domain="$1" prefix="$2" use_auth="$3"
  local prefix_norm root_dir auth_file auth_user auth_pass cfg_file
  prefix_norm="$(norm_prefix "$prefix")"

  root_dir="/var/www/${domain}${prefix_norm}/public"
  create_sample_content "$root_dir" "$prefix_norm"

  local auth_block="" creds_note=""
  if [[ "$use_auth" =~ ^[yY]$ ]]; then
    auth_user="admin"; auth_pass="$(gen_pw 24)"
    local slug_dom slug_pre; slug_dom="$(slugify "$domain")"; slug_pre="$(slugify "$prefix_norm")"
    auth_file="/etc/nginx/.htpasswd_${slug_dom}_${slug_pre}"
    install -d -m 750 -o root -g www-data /etc/nginx
    htpasswd -bBc "$auth_file" "$auth_user" "$auth_pass" >/dev/null
    chmod 640 "$auth_file"; chown root:www-data "$auth_file"
    auth_block="auth_basic \"Restricted\";\n        auth_basic_user_file ${auth_file};"
    printf "%s\n" "VHOST ${domain}${prefix_norm} BASIC_AUTH_USER=${auth_user} BASIC_AUTH_PASS=${auth_pass} HTPASSWD=${auth_file}" >> /root/credentials.txt
    creds_note=" (BasicAuth aktiviert)"
  fi

  cfg_file="/etc/nginx/sites-available/${domain}.conf"
  cat > "$cfg_file" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log warn;

    location = / { return 301 ${prefix_norm}/; }

    location ${prefix_norm}/ {
        ${auth_block}
        alias ${root_dir}/;
        index index.php index.html;
        try_files $uri $uri/ ${prefix_norm}/index.php?$query_string;
    }

    location ~ ^${prefix_norm}/(.+\.php)$ {
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME ${root_dir}/$1;
        fastcgi_pass unix:${PHP_SOCK};
    }
}
NGINX

  ln -sf "$cfg_file" "/etc/nginx/sites-enabled/$(basename "$cfg_file")"
  echo "VHOST ${domain}${prefix_norm}${creds_note}" >> /root/credentials.txt
  [ "$SILENT" = "yes" ] || echo -e "\e[1;32m[+] vHost erstellt: http://${domain}${prefix_norm}/\e[0m${creds_note}"
}

echo
echo "=== vHost-Erstellung (mehrere) ==="
while :; do
  read -rp "Neuen vHost anlegen? (y/n): " yn
  case "$yn" in
    y|Y)
      local_domain=""; while [ -z "$local_domain" ]; do read -rp "Domain (z.B. example.com): " local_domain; done
      local_prefix=""; while :; do
        read -rp "URL-Prefix (z.B. /app, /api): " local_prefix
        local_prefix="$(norm_prefix "$local_prefix")"
        [ "$local_prefix" = "/" ] && { echo "Bitte keinen reinen '/'-Prefix."; continue; }
        break
      done
      local_auth=""; while :; do
        read -rp "HTTP Basic Auth aktivieren? (y/n): " local_auth
        [[ "$local_auth" =~ ^[yYnN]$ ]] && break
      done
      add_vhost "$local_domain" "$local_prefix" "$local_auth"
      ;;
    n|N) break ;;
    *) echo "Bitte y oder n." ;;
  esac
done

if ! nginx -t; then
  err "nginx -t fehlgeschlagen. Bitte Config prüfen."
  exit 1
fi
(run systemctl reload nginx || systemctl restart nginx) || true

log "vHosts fertig."
