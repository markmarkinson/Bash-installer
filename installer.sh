#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="${BASE_DIR}/modules"
[ -f "${BASE_DIR}/installer.env" ] && . "${BASE_DIR}/installer.env"

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte als root ausführen." >&2
  exit 1
fi

trap 'ec=$?; echo -e "\n\033[1;31m[FEHLER]\033[0m Abbruch in Zeile $LINENO (Exitcode $ec)"; exit $ec' ERR

while :; do
  clear
  cat <<'MENU'
========================================
   Debian Setup – Installer
========================================
 1) System-Update (apt update)
 2) Server absichern (User, SSH, UFW, Fail2ban, Logs)
 3) Webstack installieren (nginx, PHP-FPM, MariaDB, phpMyAdmin)
 4) vHosts anlegen (interaktiv, mehrere)
 5) ALLES (1 → 4 der Reihe nach)
 6) Let's Encrypt (TLS für Domains)
 7) Neuen vHost anlegen (schnell)
 8) vHost entfernen
 9) Restore (Backups *.bak zurückspielen)
 0) Beenden
----------------------------------------
MENU
  read -rp "Auswahl: " choice
  case "${choice}" in
    1) bash "${MODULE_DIR}/10_updates.sh" ;;
    2) bash "${MODULE_DIR}/20_harden.sh" ;;
    3) bash "${MODULE_DIR}/30_web.sh" ;;
    4) bash "${MODULE_DIR}/40_vhosts.sh" ;;
    5) bash "${MODULE_DIR}/10_updates.sh"        && bash "${MODULE_DIR}/20_harden.sh"        && bash "${MODULE_DIR}/30_web.sh"        && bash "${MODULE_DIR}/40_vhosts.sh" ;;
    6) bash "${MODULE_DIR}/50_tls.sh" ;;
    7) bash "${MODULE_DIR}/41_add_vhost.sh" ;;
    8) bash "${MODULE_DIR}/60_remove_vhost.sh" ;;
    9) bash "${MODULE_DIR}/70_restore.sh" ;;
    0) echo "Bye."; exit 0 ;;
    *) echo "Ungültige Auswahl."; sleep 1 ;;
  esac
  echo
  read -rp "Weiter mit [Enter] …" _
done
