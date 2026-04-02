# ТСПУ RST Block List

Живой список IP адресов DPI/ТСПУ оборудования которое шлёт TCP RST пакеты на MTProxy серверы и рвёт соединения пользователей Telegram.

🌐 **Веб-интерфейс:** https://stats.gptru.pro:4443/rst/

## Два источника данных

### ✅ CyberOK Skipa — проверенные (обновляется раз в сутки)
Задокументированный список IP сканеров ТСПУ от независимых исследователей.
Источник: [tread-lightly/CyberOK_Skipa_ips](https://github.com/tread-lightly/CyberOK_Skipa_ips)

### 🧪 Автосбор RST — экспериментальный (обновляется раз в сутки)
Собираем IP которые шлют RST пакеты на порт 443. Только RU адреса по whois.
**Важно:** ТСПУ может подменять IP клиента — точность метода уточняется сообществом.

## Быстрая установка
```bash
# 1. Установить ipset
apt-get install -y ipset

# 2. Применить блок-лист CyberOK (рекомендуем)
curl -fsSL "https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables&src=cyberok" \
  -o /tmp/tspublock.sh && bash /tmp/tspublock.sh

# 3. Проверить (pkts должны расти)
iptables -L TSPUBLOCK -v -n

# 4. Сохранить
ipset save > /etc/ipset.conf && iptables-save > /etc/iptables/rules.v4

# 5. Автообновление CyberOK раз в сутки
(crontab -l 2>/dev/null; echo "0 3 * * * curl -fsSL https://stats.gptru.pro:4443/rst/update_cyberok.sh | bash >> /var/log/cyberok.log 2>&1") | crontab -
```

## Экспорт списка

| Формат | CyberOK | Полный |
|--------|---------|--------|
| iptables/ipset | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables&src=cyberok) | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables) |
| MikroTik .rsc | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=mikrotik&src=cyberok) | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=mikrotik) |
| Текст .txt | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=txt&src=cyberok) | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=txt) |
| ipset restore | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=ipset&src=cyberok) | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=ipset) |

## Помочь пополнить базу

Если у вас есть MTProxy сервер — запустите скрипт сбора RST пакетов:
```bash
curl -fsSL https://stats.gptru.pro:4443/rst/rst_submit.sh | sudo bash -s -- ВАШ_ПОРТ 30
```

Замените `ВАШ_ПОРТ` на порт вашего прокси (обычно 443).

## Для MikroTik
```
/import file=tspuips_mikrotik.rsc
/ip firewall filter add chain=input protocol=tcp tcp-flags=rst src-address-list=TSPUIPS action=drop
```

## Состав репозитория

| Файл | Описание |
|------|----------|
| `rst_collect.sh` | Автосбор RST IP — ставить на свой сервер в cron раз в сутки |
| `rst_submit.sh` | Сбор RST и отправка в нашу базу |
| `update_cyberok.sh` | Обновление списка CyberOK Skipa с GitHub |
| `api.php` | API: список IP, whois, статистика, экспорт |
| `collect.php` | Приёмник данных от участников |
| `index.html` | Веб-интерфейс |

## Связанные проекты

- [telemt-proxy-panel-bot-firewall](https://github.com/upe4d/telemt-proxy-panel-bot-firewall) — настройка telemt MTProxy
- [CyberOK_Skipa_ips](https://github.com/tread-lightly/CyberOK_Skipa_ips) — база сканеров ТСПУ
- [nikr-dev/mikrotik-adresslist-from-url](https://github.com/nikr-dev/mikrotik-adresslist-from-url) — автозагрузка в MikroTik
- Telegram канал: [@u_pre](https://t.me/u_pre)
