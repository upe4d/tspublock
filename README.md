# ТСПУ RST Block List

Живой список IP адресов DPI/ТСПУ оборудования которое шлёт поддельные TCP RST пакеты на MTProxy серверы и рвёт соединения пользователей Telegram.

🌐 **Веб-интерфейс:** https://stats.gptru.pro:4443/rst/

## Как это работает

ТСПУ вклинивается в соединение между клиентом и MTProxy сервером и шлёт RST пакеты со своих реальных IP. Сервер думает что клиент отключился — Telegram handshake timeout. Мы собираем эти IP и блокируем через iptables + ipset.

## Быстрая установка на свой MTProxy сервер
```bash
# 1. Установить ipset
apt-get install -y ipset

# 2. Скачать и применить актуальный блок-лист
curl -fsSL "https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables" -o /tmp/tspublock.sh && bash /tmp/tspublock.sh

# 3. Проверить (pkts должны расти)
iptables -L TSPUBLOCK -v -n

# 4. Сохранить
ipset save > /etc/ipset.conf && iptables-save > /etc/iptables/rules.v4

# 5. Автообновление каждые 2 минуты
curl -fsSL https://stats.gptru.pro:4443/rst/rst_collect.sh -o /opt/rst_collect.sh && chmod +x /opt/rst_collect.sh && (crontab -l 2>/dev/null; echo "*/2 * * * * /opt/rst_collect.sh >> /var/log/rst_collect.log 2>&1") | crontab -
```

## Помочь пополнить базу

Если у вас есть MTProxy сервер — запустите скрипт. Он 30 секунд собирает RST пакеты и отправляет новые IP в нашу базу:
```bash
curl -fsSL https://stats.gptru.pro:4443/rst/rst_submit.sh | sudo bash -s -- ВАШ_ПОРТ 30
```

## Экспорт списка

| Формат | Ссылка |
|--------|--------|
| iptables/ipset bash скрипт | https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables |
| MikroTik .rsc | https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=mikrotik |
| Текст .txt | https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=txt |
| ipset restore | https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=ipset |

## Для MikroTik
```
/import file=tspuips_mikrotik.rsc
/ip firewall filter add chain=input protocol=tcp tcp-flags=rst src-address-list=TSPUIPS action=drop
```

## Состав репозитория

| Файл | Описание |
|------|----------|
| `rst_collect.sh` | Автосбор RST IP — ставить на свой сервер в cron |
| `rst_submit.sh` | Сбор и отправка IP в нашу базу |
| `api.php` | API: список IP, whois, статистика, экспорт |
| `collect.php` | Приёмник данных от участников |
| `index.html` | Веб-интерфейс |

## Связанные проекты

- [telemt-proxy-panel-bot-firewall](https://github.com/upe4d/telemt-proxy-panel-bot-firewall) — основной репо с настройкой telemt
- [CyberOK_Skipa_ips](https://github.com/tread-lightly/CyberOK_Skipa_ips) — база сканеров ТСПУ
- Telegram канал: [@u_pre](https://t.me/u_pre)
