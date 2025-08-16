#!/usr/bin/env bash
set -Eeuo pipefail

: "${SILENT:=yes}"     # yes = still, no = verbose
: "${REMOTE_SYSLOG:=}" # z.B. logs.example.net

log()  { [ "$SILENT" = "yes" ] || echo -e "\e[1;32m[+] $*\e[0m"; }
warn() { [ "$SILENT" = "yes" ] || echo -e "\e[1;33m[!] $*\e[0m"; }
err()  { echo -e "\e[1;31m[-] $*\e[0m" >&2; }

run()   { if [ "$SILENT" = "yes" ]; then "$@" >/dev/null; else "$@"; fi; }
run_q() { if [ "$SILENT" = "yes" ]; then "$@" >/dev/null 2>/dev/null; else "$@"; fi; }

require_root() { [ "$(id -u)" -eq 0 ] || { err "Bitte als root ausführen."; exit 1; } }
file_backup()  { local f="$1"; if [ -f "$f" ] && [ ! -f "${f}.bak" ]; then cp -a "$f" "${f}.bak"; fi; }

export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
export APT_LISTCHANGES_FRONTEND=none
export NEEDRESTART_SILENT=1

APT_INSTALL_OPTS=(-y -o Dpkg::Use-Pty=0 -o Dpkg::Progress-Fancy=false)
APT_PURGE_OPTS=(-y -o Dpkg::Use-Pty=0 -o Dpkg::Progress-Fancy=false)
[ "$SILENT" = "yes" ] && { APT_INSTALL_OPTS+=(-qq); APT_PURGE_OPTS+=(-qq); }

apt_update()  { if [ "$SILENT" = "yes" ]; then apt-get update -qq >/dev/null; else apt-get update -q; fi; }
apt_install() { run apt-get "${APT_INSTALL_OPTS[@]}" install "$@"; }
apt_purge()   { run apt-get "${APT_PURGE_OPTS[@]}" purge "$@"; }
apt_auto_rm() { run apt-get "${APT_PURGE_OPTS[@]}" autoremove; }

gen_pw() {
  local len="${1:-24}" pw pool
  local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@#%+=,.!^*(){}?~_/'
  while :; do
    pool="$(head -c 4096 /dev/urandom | tr -dc "$chars")"
    [ "${#pool}" -ge "$len" ] || continue
    pw="${pool:0:$len}"
    grep -q '[[:upper:]]'  <<<"$pw" || continue
    grep -q '[[:lower:]]'  <<<"$pw" || continue
    grep -q '[[:digit:]]'  <<<"$pw" || continue
    grep -q '[^[:alnum:]]' <<<"$pw" || continue
    printf "%s" "$pw"; return 0
  done
}

gen_usernames() {
  local -a FIRST=(bernd markus ralf andreas martin sebastian tobias daniel michael patrick kai jan oliver thomas philipp alex)
  local -a LAST=(Stelter Meyer Bering Schmitt Mueller Schneider Fischer Weber Becker Wagner Hoffmann Schulz Koch Richter Klein Wolf Schroeder Neumann Schwarz Zimmermann)
  local f="${FIRST[$RANDOM%${#FIRST[@]}]}"
  local l="${LAST[$RANDOM%${#LAST[@]}]}"
  local d; printf -v d "%04d" "$((RANDOM%10000))"
  local pretty="${f}${l}${d}"
  local login; login="$(echo -n "$pretty" | tr '[:upper:]' '[:lower:]')"
  echo "$pretty;$login"
}

slugify() { echo -n "$1" | tr -c 'A-Za-z0-9' '_'; }
norm_prefix() {
  local p="$1"
  p="$(echo -n "$p" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [[ "$p" =~ ^/ ]] || p="/$p"
  p="$(echo -n "$p" | sed -E 's#/+#/#g')"
  [ "$p" != "/" ] && p="${p%/}"
  echo -n "$p"
}

detect_php_sock() {
  local s
  for s in /run/php/php*-fpm.sock; do
    [ -S "$s" ] && { echo -n "$s"; return 0; }
  done
  echo -n ""; return 1
}

is_port_in_use() {
  local p="$1" out
  out="$(ss -H -ltn "sport = :$p" 2>/dev/null || true)"; [ -n "$out" ]
}

set_sshd_opt() {
  local key="$1" val="$2" cfg="/etc/ssh/sshd_config"
  if grep -qE "^[#[:space:]]*${key}\b" "$cfg"; then
    sed -i -E "s|^[#[:space:]]*${key}\b.*|${key} ${val}|" "$cfg"
  else
    echo "${key} ${val}" >> "$cfg"
  fi
}

ensure_swap() {
  if ! swapon --noheadings --summary >/dev/null 2>&1 || [ -z "$(swapon --noheadings --summary)" ]; then
    log "Kein Swap gefunden – erstelle 2G Swapfile…"
    if ! run fallocate -l 2G /swapfile; then run dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none; fi
    run chmod 600 /swapfile
    run mkswap /swapfile
    run swapon /swapfile
    grep -qE '^\s*/swapfile\s' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    run sysctl -w vm.swappiness=10 || true
  fi
}

create_sample_content() {
  local root="$1" prefix="$2"
  install -d -m 755 "$root"; chown -R www-data:www-data "$root"
  [ -f "${root}/index.php" ] || cat >"${root}/index.php" <<PHP
<?php
header('Content-Type: application/json; charset=utf-8');
echo json_encode(['status'=>'ok','message'=>'vhost ready','prefix'=>'${prefix}','time'=>date('c')]);
PHP
  [ -f "${root}/app.js" ] || cat >"${root}/app.js" <<'JS'
document.addEventListener('DOMContentLoaded',()=>{console.log('vhost: JS ready')});
JS
  [ -f "${root}/index.html" ] || cat >"${root}/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>vhost</title></head><body>
<h1>Static index for ${prefix}</h1><script src="${prefix}/app.js"></script></body></html>
HTML
}
