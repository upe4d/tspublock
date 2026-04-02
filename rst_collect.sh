#!/bin/bash
# rst_collect.sh — Автосбор IP ТСПУ которые шлют RST пакеты
# Фильтры: только TTL=40, только RU IP (через whois)
# Cron: */2 * * * * /opt/rst_collect.sh >> /var/log/rst_collect.log 2>&1

IPSET_NAME="TSPUIPS"
LOG_PREFIX="RST_AUTO"
SAMPLE_SECS=30
ADDED_FILE="/etc/rst_added.txt"

# Whitelist — Telegram DC и свой сервер
WHITELIST=(149.154.160.0/20 149.154.164.0/22 149.154.168.0/22 91.108.4.0/22 91.108.8.0/22 91.108.56.0/22 91.105.192.0/23 95.161.76.0/22 149.154.161.0/24 149.154.167.0/24 89.22.227.9 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $1"; }

[[ $EUID -ne 0 ]] && { log "ERROR: нужен root"; exit 1; }
! ipset list $IPSET_NAME &>/dev/null && { log "ERROR: ipset не существует"; exit 1; }

log "=== Сбор RST (TTL=40, только RU) ${SAMPLE_SECS}s ==="

# Логируем RST на порт 443 не из нашего списка
iptables -I INPUT 1 -p tcp --tcp-flags RST RST --dport 443 -m set ! --match-set $IPSET_NAME src -j LOG --log-prefix "${LOG_PREFIX}: " --log-level 4
sleep $SAMPLE_SECS
iptables -D INPUT 1

# Берём только IP с TTL=40 — характерный признак ТСПУ
NEW_IPS=$(dmesg | grep "${LOG_PREFIX}:" | grep "TTL=40 " | grep -oP 'SRC=\K[\d.]+' | sort -u)

if [[ -z "$NEW_IPS" ]]; then
    log "Новых RST с TTL=40 не найдено"
    exit 0
fi

log "Кандидатов с TTL=40: $(echo "$NEW_IPS" | wc -l)"

touch "$ADDED_FILE"
ADDED=0

while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue

    # Проверяем whitelist
    WL=0
    for entry in "${WHITELIST[@]}"; do
        [[ "$entry" == "$ip" ]] && { WL=1; break; }
        if [[ "$entry" == *"/"* ]]; then
            python3 -c "import ipaddress; exit(0 if ipaddress.ip_address('$ip') in ipaddress.ip_network('$entry',strict=False) else 1)" 2>/dev/null && { WL=1; break; }
        fi
    done
    [[ $WL -eq 1 ]] && { log "  SKIP whitelist: $ip"; continue; }

    # Проверяем нет ли уже в ipset
    ipset test $IPSET_NAME "$ip" &>/dev/null && continue

    # Проверяем страну через whois — только RU
    country=$(whois "$ip" 2>/dev/null | grep -i "^country:" | head -1 | awk '{print $2}' | tr -d '\r')
    if [[ "$country" != "RU" ]]; then
        log "  SKIP non-RU: $ip (country=${country:-unknown})"
        continue
    fi

    # Добавляем
    ipset add $IPSET_NAME "$ip" 2>/dev/null && {
        log "  ADDED RU TTL=40: $ip"
        echo "$(ts) $ip" >> "$ADDED_FILE"
        ((ADDED++))
    }

done <<< "$NEW_IPS"

log "Добавлено: $ADDED | Итого: $(ipset list $IPSET_NAME | grep -c '^[0-9]')"
[[ $ADDED -gt 0 ]] && { ipset save > /etc/ipset.conf; iptables-save > /etc/iptables/rules.v4; log "Сохранено"; }
log "=== Готово ==="
