#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/00_common.sh"
require_root

apt_install ca-certificates curl gnupg lsb-release apache2-utils chrony rsyslog logrotate

ensure_swap
if systemd-detect-virt --container >/dev/null 2>&1; then
  log "Container erkannt – Kernel-Pakete auf HOLD."
  run apt-mark hold linux-image-amd64 linux-image-cloud-amd64 linux-headers-amd64 linux-headers-cloud-amd64 || true
fi

apt_purge avahi-daemon avahi-utils cups rpcbind exim4 exim4-base exim4-daemon-light || true
run_q systemctl disable --now avahi-daemon cups rpcbind exim4 || true
apt_auto_rm

SSH_PORT=""
for _try in $(seq 1 50); do
  cand="$(shuf -i 35000-50000 -n 1)"
  if ! is_port_in_use "$cand"; then SSH_PORT="$cand"; break; fi
done
[ -n "$SSH_PORT" ] || { err "Konnte keinen freien SSH-Port finden."; exit 1; }

install -m 600 -o root -g root /dev/null /root/credentials.txt
IFS=';' read -r NEW_USER_PRETTY NEW_USER <<<"$(gen_usernames)"
USER_PASS="$(gen_pw 24)"
if ! id -u "${NEW_USER}" >/dev/null 2>&1; then
  run adduser --gecos "${NEW_USER_PRETTY}" --disabled-password "${NEW_USER}" || true
fi
echo "${NEW_USER}:${USER_PASS}" | run chpasswd
run usermod -aG sudo "${NEW_USER}"

file_backup /etc/ssh/sshd_config
set_sshd_opt "PermitRootLogin" "no"
set_sshd_opt "Port" "${SSH_PORT}"
set_sshd_opt "MaxAuthTries" "3"
set_sshd_opt "MaxSessions"  "2"
set_sshd_opt "LoginGraceTime" "30"
set_sshd_opt "PasswordAuthentication" "yes"
set_sshd_opt "ChallengeResponseAuthentication" "no"
set_sshd_opt "UsePAM" "yes"
run systemctl restart ssh

apt_install ufw
run ufw --force reset
run ufw default deny incoming
run ufw default allow outgoing
run ufw allow "${SSH_PORT}"/tcp
run ufw allow 80/tcp
run ufw allow 443/tcp
run ufw logging on
run ufw --force enable

apt_install fail2ban
install -d /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<JAIL
[sshd]
enabled   = true
port      = ${SSH_PORT}
bantime   = 1h
findtime  = 10m
maxretry  = 3
backend   = systemd
JAIL
run systemctl enable --now fail2ban
run systemctl restart fail2ban

file_backup /etc/systemd/journald.conf
sed -i -E 's/^#?Storage=.*/Storage=persistent/; s/^#?ForwardToSyslog=.*/ForwardToSyslog=yes/' /etc/systemd/journald.conf
run systemd-tmpfiles --create || true
run systemctl restart systemd-journald

if [ -n "${REMOTE_SYSLOG}" ]; then
  cat >/etc/rsyslog.d/90-remote.conf <<RS
*.* @@${REMOTE_SYSLOG}:514;RSYSLOG_SyslogProtocol23Format
RS
  run systemctl restart rsyslog
fi

apt_install unattended-upgrades apt-listchanges
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' >/etc/apt/apt.conf.d/20auto-upgrades
run dpkg-reconfigure -fnoninteractive unattended-upgrades

{
  echo "NEW_USER_LOGIN=${NEW_USER}"
  echo "NEW_USER_DISPLAY=${NEW_USER_PRETTY}"
  echo "NEW_USER_PASSWORD=${USER_PASS}"
  echo "SSH_PORT=${SSH_PORT}"
} >> /root/credentials.txt

log "Absicherung fertig. Login: ${NEW_USER} | SSH-Port: ${SSH_PORT}"
