#!/bin/bash
# update_cyberok.sh — Автообновление списка CyberOK Skipa с GitHub
# Cron: 0 3 * * * curl -fsSL https://stats.gptru.pro:4443/rst/update_cyberok.sh | bash
#
# CHANGELOG:
# v1.2.0 - Фикс: ipset создаётся с maxelem 65536 (issue #1)
#          Фикс: правильный порядок destroy через flush (issue #2)
#          Фикс: создание /etc/iptables/ если не существует
# v1.1.0 - Добавлен альтернативный источник skipa_checkpoint.csv
# v1.0.0 - Базовая версия

IPSET_NAME="TSPUIPS"
CHAIN_NAME="TSPUBLOCK"
CYBEROK_URL="https://raw.githubusercontent.com/tread-lightly/CyberOK_Skipa_ips/main/lists/skipa_cidr.txt"
CYBEROK_FILE="/etc/cyberok_ips.txt"
ADDED_CYBEROK="/etc/cyberok_added.txt"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $1"; }

log "=== Обновление CyberOK Skipa ==="

# Создаём ipset с нужным лимитом если не существует
if ! ipset list "$IPSET_NAME" &>/dev/null; then
    log "Создаём ipset $IPSET_NAME с maxelem 65536..."
    ipset create "$IPSET_NAME" hash:net maxelem 65536
fi

# Проверяем что maxelem достаточный — если нет, пересоздаём
MAXELEM=$(ipset list "$IPSET_NAME" | grep -oP 'maxelem \K\d+')
if [[ "$MAXELEM" -lt 65536 ]]; then
    log "maxelem=$MAXELEM мало, пересоздаём set с maxelem 65536..."
    # Сначала убираем правило iptables если есть
    iptables -D "$CHAIN_NAME" -p tcp --tcp-flags RST RST -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
    # Флашим и уничтожаем
    ipset flush "$IPSET_NAME" 2>/dev/null
    ipset destroy "$IPSET_NAME" 2>/dev/null
    # Создаём заново
    ipset create "$IPSET_NAME" hash:net maxelem 65536
    # Восстанавливаем правило
    iptables -N "$CHAIN_NAME" 2>/dev/null
    iptables -I INPUT 1 -j "$CHAIN_NAME" 2>/dev/null
    iptables -I "$CHAIN_NAME" -p tcp --tcp-flags RST RST -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null
fi

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
    ip=$(echo "$line" | grep -oP '^[\d.]+(?:/\d+)?')
    [[ -z "$ip" ]] && continue
    if ! grep -q "^$ip$" "$CYBEROK_FILE" 2>/dev/null; then
        echo "$ip" >> "$CYBEROK_FILE"
    fi
    ipset test $IPSET_NAME "$ip" &>/dev/null && continue
    ipset add $IPSET_NAME "$ip" 2>/dev/null && {
        log "  ADDED: $ip"
        echo "$(ts) $ip cyberok" >> "$ADDED_CYBEROK"
        ((ADDED++))
    }
done < "$TMP"
rm -f "$TMP"

log "Добавлено новых: $ADDED"

# Сохраняем правила
ipset save > /etc/ipset.conf

# Сохраняем iptables (совместимо с ufw и iptables-persistent)
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save 2>/dev/null
elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
else
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
fi

log "=== Готово ==="
