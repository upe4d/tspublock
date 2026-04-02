#!/bin/bash
IPSET_NAME="TSPUIPS"
LOG_PREFIX="RST_AUTO"
SAMPLE_SECS=30
ADDED_FILE="/etc/rst_added.txt"
WHITELIST=(149.154.160.0/20 149.154.164.0/22 149.154.168.0/22 91.108.4.0/22 91.108.8.0/22 91.108.56.0/22 91.105.192.0/23 95.161.76.0/22 149.154.161.0/24 149.154.167.0/24 89.22.227.9 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)
ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $1"; }
[[ $EUID -ne 0 ]] && { log "ERROR: нужен root"; exit 1; }
! ipset list $IPSET_NAME &>/dev/null && { log "ERROR: ipset не существует"; exit 1; }
iptables -I INPUT 1 -p tcp --tcp-flags RST RST --dport 443 -m set ! --match-set $IPSET_NAME src -j LOG --log-prefix "${LOG_PREFIX}: " --log-level 4
sleep $SAMPLE_SECS
iptables -D INPUT 1
NEW_IPS=$(dmesg | grep "${LOG_PREFIX}:" | grep -oP 'SRC=\K[\d.]+' | sort -u)
[[ -z "$NEW_IPS" ]] && { log "Новых IP нет"; exit 0; }
touch "$ADDED_FILE"
ADDED=0
while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    WL=0
    for entry in "${WHITELIST[@]}"; do
        [[ "$entry" == "$ip" ]] && { WL=1; break; }
        if [[ "$entry" == *"/"* ]]; then
            python3 -c "import ipaddress; exit(0 if ipaddress.ip_address('$ip') in ipaddress.ip_network('$entry',strict=False) else 1)" 2>/dev/null && { WL=1; break; }
        fi
    done
    [[ $WL -eq 1 ]] && { log "  SKIP whitelist: $ip"; continue; }
    ipset test $IPSET_NAME "$ip" &>/dev/null && continue
    ipset add $IPSET_NAME "$ip" 2>/dev/null && { log "  ADDED: $ip"; echo "$(ts) $ip" >> "$ADDED_FILE"; ((ADDED++)); }
done <<< "$NEW_IPS"
log "Добавлено: $ADDED | Итого в ipset: $(ipset list $IPSET_NAME | grep -c '^[0-9]')"
[[ $ADDED -gt 0 ]] && { ipset save > /etc/ipset.conf; iptables-save > /etc/iptables/rules.v4; log "Сохранено"; }
