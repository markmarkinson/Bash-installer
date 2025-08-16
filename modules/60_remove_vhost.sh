#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/00_common.sh"
require_root

mapfile -t CONF_LIST < <(ls -1 /etc/nginx/sites-available/*.conf 2>/dev/null | grep -v '/default$' || true)
if [ "${#CONF_LIST[@]}" -eq 0 ]; then
  err "Keine vHost-Konfigurationen gefunden."
  exit 1
fi

echo "Gefundene vHosts:"
i=1
for c in "${CONF_LIST[@]}"; do
  b="$(basename "$c")"
  echo "  ${i}) ${b}"
  i=$((i+1))
done

read -rp "Nummern zum Entfernen (z.B. 1 3 5) oder 'all': " selection
sel_items=()
if [[ "$selection" = "all" ]]; then
  sel_items=("${CONF_LIST[@]}")
else
  for n in $selection; do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    idx=$((n-1))
    [ $idx -ge 0 ] && [ $idx -lt ${#CONF_LIST[@]} ] && sel_items+=("${CONF_LIST[$idx]}")
  done
fi

[ "${#sel_items[@]}" -gt 0 ] || { err "Keine gültige Auswahl."; exit 1; }

for cfg in "${sel_items[@]}"; do
  b="$(basename "$cfg")"
  echo "Entferne vHost ${b}…"
  mapfile -t ALIASES < <(grep -E '^\s*alias\s+/' "$cfg" 2>/dev/null | awk '{print $2}' | sed -E 's/;?$//' || true)
  rm -f "/etc/nginx/sites-enabled/${b}"
  rm -f "$cfg"

  if [ "${#ALIASES[@]}" -gt 0 ]; then
    echo "Gefundene Web-Verzeichnisse:"
    for a in "${ALIASES[@]}"; do echo " - $a"; done
    read -rp "Diese Verzeichnisse löschen? (y/n): " del
    if [[ "$del" =~ ^[yY]$ ]]; then
      for a in "${ALIASES[@]}"; do
        parent="$(dirname "$a")"
        base="$(dirname "$parent")"
        [ -d "$base" ] && rm -rf "$base"
      done
    fi
  fi
done

if ! nginx -t; then
  err "nginx -t fehlgeschlagen. Bitte Config prüfen."
  exit 1
fi
(run systemctl reload nginx || systemctl restart nginx) || true

log "Entfernen abgeschlossen."
