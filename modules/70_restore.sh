#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/00_common.sh"
require_root

SEARCH_PATHS=(/etc/nginx /etc/ssh /etc/fail2ban /etc/systemd /etc/rsyslog.d)
mapfile -t BAKS < <(find "${SEARCH_PATHS[@]}" -maxdepth 3 -type f -name "*.bak" 2>/dev/null | sort || true)

if [ "${#BAKS[@]}" -eq 0 ]; then
  err "Keine *.bak-Dateien gefunden."
  exit 1
fi

echo "Gefundene Backups:"
i=1
for f in "${BAKS[@]}"; do
  echo "  ${i}) $f"
  i=$((i+1))
done

echo
read -rp "Alles wiederherstellen? (y/n): " all
RESTORE_LIST=()
if [[ "$all" =~ ^[yY]$ ]]; then
  RESTORE_LIST=("${BAKS[@]}")
else
  read -rp "Nummern wählen (z.B. 1 3 5): " nums
  for n in $nums; do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    idx=$((n-1))
    [ $idx -ge 0 ] && [ $idx -lt ${#BAKS[@]} ] && RESTORE_LIST+=("${BAKS[$idx]}")
  done
fi

[ "${#RESTORE_LIST[@]}" -gt 0 ] || { err "Keine gültige Auswahl."; exit 1; }

changed_nginx=0; changed_ssh=0; changed_journal=0; changed_rsyslog=0; changed_f2b=0

ts="$(date +%Y%m%d%H%M%S)"
for bak in "${RESTORE_LIST[@]}"; do
  orig="${bak%.bak}"
  echo "Restore: ${bak} -> ${orig}"
  if [ -f "$orig" ]; then cp -a "$orig" "${orig}.pre-restore.${ts}"; fi
  install -m 644 "$bak" "$orig"
  case "$orig" in
    /etc/nginx/*) changed_nginx=1 ;;
    /etc/ssh/*) changed_ssh=1 ;;
    /etc/systemd/*journald.conf) changed_journal=1 ;;
    /etc/rsyslog.d/*) changed_rsyslog=1 ;;
    /etc/fail2ban/*) changed_f2b=1 ;;
  esac
done

if [ $changed_nginx -eq 1 ]; then
  nginx -t && (systemctl reload nginx || systemctl restart nginx) || err "nginx reload fehlgeschlagen"
fi
[ $changed_ssh -eq 1 ] && systemctl restart ssh || true
[ $changed_journal -eq 1 ] && systemctl restart systemd-journald || true
[ $changed_rsyslog -eq 1 ] && systemctl restart rsyslog || true
[ $changed_f2b -eq 1 ] && systemctl restart fail2ban || true

log "Restore abgeschlossen."
