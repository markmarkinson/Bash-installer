#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/00_common.sh"
require_root

echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect none' | debconf-set-selections
echo 'phpmyadmin phpmyadmin/dbconfig-install boolean false'       | debconf-set-selections
apt_install nginx mariadb-server php-fpm php-mysql php-cli php-json php-common php-mbstring php-zip php-gd php-curl php-xml phpmyadmin

PHP_SOCK="$(detect_php_sock || true)"
[ -n "$PHP_SOCK" ] || { warn "Kein PHP-FPM Socket gefunden, nutze Standardpfad…"; PHP_SOCK="/run/php/php-fpm.sock"; }

file_backup /etc/nginx/nginx.conf
sed -i -E 's/^[[:space:]]*server_tokens[[:space:]]+on;?/    server_tokens off;/' /etc/nginx/nginx.conf || true

cat >/etc/nginx/conf.d/limit_req_pma.conf <<'NG'
limit_req_zone $binary_remote_addr zone=pma:10m rate=20r/m;
NG

install -m 600 -o root -g root /dev/null /root/credentials.txt
PMA_HTPASSWD_FILE="/etc/nginx/.htpasswd_pma"
PMA_BASIC_USER="pmaadmin"
PMA_BASIC_PASS="$(gen_pw 24)"
install -d -m 750 -o root -g www-data /etc/nginx
htpasswd -bBc "${PMA_HTPASSWD_FILE}" "${PMA_BASIC_USER}" "${PMA_BASIC_PASS}" >/dev/null
chmod 640 "${PMA_HTPASSWD_FILE}"; chown root:www-data "${PMA_HTPASSWD_FILE}"
{
  echo "PMA_BASIC_AUTH_USER=${PMA_BASIC_USER}"
  echo "PMA_BASIC_AUTH_PASS=${PMA_BASIC_PASS}"
  echo "PMA_HTPASSWD=${PMA_HTPASSWD_FILE}"
} >> /root/credentials.txt

install -d /etc/nginx/snippets
cat > /etc/nginx/snippets/pma_protected.conf <<PMA
location = /pma-db {
    if (\$host !~* "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$") { return 404; }
    return 301 /pma-db/;
}
location ~ ^/pma-db/(.+\.php)$ {
    if (\$host !~* "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$") { return 404; }
    auth_basic "Restricted phpMyAdmin";
    auth_basic_user_file ${PMA_HTPASSWD_FILE};
    include snippets/fastcgi-php.conf;
    fastcgi_param SCRIPT_FILENAME /usr/share/phpmyadmin/\$1;
    fastcgi_pass unix:${PHP_SOCK};
}
location /pma-db/ {
    if (\$host !~* "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$") { return 404; }
    auth_basic "Restricted phpMyAdmin";
    auth_basic_user_file ${PMA_HTPASSWD_FILE};
    alias /usr/share/phpmyadmin/;
    index index.php index.html;
    location ~* ^/pma-db/(doc|sql|setup)/ { deny all; }
    try_files \$uri \$uri/ /pma-db/index.php?\$query_string;
    limit_req zone=pma burst=5 nodelay;
    limit_req_status 429;
}
PMA

rm -f /etc/nginx/sites-enabled/00-ip-redirect.conf /etc/nginx/sites-available/00-ip-redirect.conf
rm -f /etc/nginx/conf.d/map_is_ip.conf

file_backup /etc/nginx/sites-available/default
cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log warn;

    include /etc/nginx/snippets/pma_protected.conf;

    location / {
        if ($host ~* "^[0-9]{1,3}(\.[0-9]{1,3}){3}$") { return 301 https://www.google.com$request_uri; }
        return 404;
    }
}
NGINX

nginx -t
(run systemctl reload nginx || systemctl restart nginx) || true

install -d /etc/fail2ban/filter.d /etc/fail2ban/jail.d
cat >/etc/fail2ban/filter.d/nginx-404-burst.conf <<'FIL'
[Definition]
failregex = ^<HOST> - - \[.*\] "([A-Z]+) .*" 404
ignoreregex =
FIL
cat >/etc/fail2ban/filter.d/nginx-req-limit.conf <<'FIL'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD) .*" (429|503)
ignoreregex =
FIL
cat >/etc/fail2ban/filter.d/nginx-phpmyadmin.conf <<'FIL'
[Definition]
failregex = ^<HOST> - - \[.*\] "(GET|POST|HEAD) /pma-db.*" (401|403|404)
ignoreregex =
FIL
cat >/etc/fail2ban/jail.d/nginx.local <<'JAIL'
[nginx-404-burst]
enabled   = true
port      = http,https
filter    = nginx-404-burst
logpath   = /var/log/nginx/access.log
findtime  = 10m
maxretry  = 20
bantime   = 1h

[nginx-req-limit]
enabled   = true
filter    = nginx-req-limit
port      = http,https
logpath   = /var/log/nginx/access.log
findtime  = 10m
maxretry  = 15
bantime   = 2h

[nginx-phpmyadmin]
enabled   = true
port      = http,https
filter    = nginx-phpmyadmin
logpath   = /var/log/nginx/access.log
findtime  = 10m
maxretry  = 10
bantime   = 2h

[nginx-http-auth]
enabled   = true
port      = http,https
filter    = nginx-http-auth
logpath   = /var/log/nginx/error.log
findtime  = 10m
maxretry  = 5
bantime   = 2h
JAIL

systemctl restart fail2ban || true

log "Webstack bereit. phpMyAdmin: http://<SERVER-IP>/pma-db (Basic-Auth)"
