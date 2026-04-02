#!/bin/bash
# update_cyberok.sh — Автообновление списка CyberOK Skipa с GitHub
# Cron: 0 3 * * * curl -fsSL https://stats.gptru.pro:4443/rst/update_cyberok.sh | bash

IPSET_NAME="TSPUIPS"
CYBEROK_URL="https://raw.githubusercontent.com/tread-lightly/CyberOK_Skipa_ips/main/lists/skipa_cidr.txt"
CYBEROK_FILE="/etc/cyberok_ips.txt"
ADDED_CYBEROK="/etc/cyberok_added.txt"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $1"; }

log "=== Обновление CyberOK Skipa ==="

# Скачиваем список
TMP=$(mktemp)
if ! curl -fsSL "$CYBEROK_URL" -o "$TMP" 2>/dev/null; then
    # Пробуем альтернативный файл
    curl -fsSL "https://raw.githubusercontent.com/tread-lightly/CyberOK_Skipa_ips/main/lists/skipa_checkpoint.csv" -o "$TMP" 2>/dev/null
fi

COUNT=$(wc -l < "$TMP" 2>/dev/null || echo 0)
if [[ $COUNT -lt 5 ]]; then
    log "ERROR: список слишком короткий ($COUNT строк)"
    rm -f "$TMP"
    exit 1
fi

log "Скачано: $COUNT записей"

# Парсим IP/подсети — фильтруем комментарии
ADDED=0
while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r' | sed 's/#.*//' | xargs)
    [[ -z "$line" ]] && continue
    # Берём только IP и подсети
    ip=$(echo "$line" | grep -oP '^[\d.]+(?:/\d+)?')
    [[ -z "$ip" ]] && continue

    # Помечаем как CyberOK в файле
    if ! grep -q "^$ip$" "$CYBEROK_FILE" 2>/dev/null; then
        echo "$ip" >> "$CYBEROK_FILE"
    fi

    # Добавляем в ipset если нет
    ipset test $IPSET_NAME "$ip" &>/dev/null && continue
    ipset add $IPSET_NAME "$ip" 2>/dev/null && {
        log "  ADDED: $ip"
        echo "$(ts) $ip cyberok" >> "$ADDED_CYBEROK"
        ((ADDED++))
    }
done < "$TMP"

rm -f "$TMP"
log "Добавлено новых: $ADDED"
[[ $ADDED -gt 0 ]] && ipset save > /etc/ipset.conf

log "=== Готово ==="
