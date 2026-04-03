#!/bin/bash
python3 << 'PYEOF'
import subprocess, os

cyberok = set(open('/etc/cyberok_ips.txt').read().strip().splitlines())
cyberok_clean = set(ip.replace('/32','') for ip in cyberok)

raw = subprocess.check_output(['sudo','ipset','list','TSPUIPS']).decode()
auto_ips = []
for line in raw.splitlines():
    line = line.strip()
    if not line or not line[0].isdigit(): continue
    if line.replace('/32','') not in cyberok_clean:
        auto_ips.append(line)

with open('/root/tspublock/auto_collected.txt','w') as f:
    f.write('# Автособранные RST IP — только RU, эксперимент\n')
    f.write(f'# Всего: {len(auto_ips)}\n\n')
    f.write('\n'.join(sorted(auto_ips)))

print(f'Обновлено: {len(auto_ips)} IP')
PYEOF

cd /root/tspublock
git add auto_collected.txt
git commit -m "Автообновление auto_collected.txt $(date '+%Y-%m-%d')" 2>/dev/null
git push origin master 2>/dev/null
