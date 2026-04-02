#!/bin/bash
# rst_submit.sh — Сбор RST IP и отправка в базу gptru.pro
# Использование: bash rst_submit.sh [порт] [секунды]
# Пример:        bash rst_submit.sh 443 30
#
# Требования: Linux, root, iptables, curl, python3

PORT=${1:-443}
SECS=${2:-30}
API="https://stats.gptru.pro:4443/rst/collect.php"
TOKEN="upe4d_rst_2026"
LOG_PREFIX="RST_SUBMIT"

# Whitelist — не отправляем Telegram DC
WHITELIST="^(149\.154\.|91\.108\.|91\.105\.|95\.161\.|127\.|10\.|192\.168\.|172\.1[6-9]\.|172\.2[0-9]\.)"

[[ $EUID -ne 0 ]] && { echo "Нужен root: sudo bash $0"; exit 1; }
command -v ipset &>/dev/null || { echo "Установите ipset: apt install ipset"; exit 1; }

echo "=== RST Collector для stats.gptru.pro/rst ==="
echo "Порт: $PORT | Сбор: ${SECS}с"
echo ""

# Добавляем временное правило логирования
iptables -I INPUT 1 \
    -p tcp --tcp-flags RST RST \
    --dport "$PORT" \
    -j LOG --log-prefix "${LOG_PREFIX}: " --log-level 4

echo "Собираем RST пакеты ${SECS} секунд..."
sleep "$SECS"

# Удаляем правило
iptables -D INPUT 1

# Собираем уникальные IP
IPS=$(dmesg | grep "${LOG_PREFIX}:" | grep -oP 'SRC=\K[\d.]+' | grep -vE "$WHITELIST" | sort -u)

if [[ -z "$IPS" ]]; then
    echo "RST пакетов не обнаружено на порту $PORT"
    exit 0
fi

COUNT=$(echo "$IPS" | wc -l)
echo "Найдено уникальных IP: $COUNT"
echo "$IPS"
echo ""

# Формируем JSON и отправляем
JSON=$(python3 -c "
import json, sys
ips = sys.stdin.read().strip().split('\n')
print(json.dumps({'ips': ips, 'token': '$TOKEN'}))
" <<< "$IPS")

echo "Отправляем в базу..."
RESP=$(curl -sf -X POST "$API" \
    -H "Content-Type: application/json" \
    -d "$JSON" 2>/dev/null)

if [[ $? -eq 0 ]]; then
    echo "Ответ: $RESP"
else
    echo "Ошибка отправки. Список IP для ручного добавления:"
    echo "$IPS"
fi
