# ТСПУ RST Block List

Живой список IP адресов DPI/ТСПУ оборудования которое шлёт TCP RST пакеты на MTProxy серверы и рвёт соединения пользователей Telegram.

🌐 **Веб-интерфейс:** https://stats.gptru.pro:4443/rst/

## Три источника данных

### ✅ CyberOK Skipa — проверенные (обновляется раз в сутки)

Задокументированный список IP сканеров ТСПУ от независимых исследователей.  
Источник: [tread-lightly/CyberOK_Skipa_ips](https://github.com/tread-lightly/CyberOK_Skipa_ips)

### 🏛️ GOVIPS — подсети госорганов РФ (обновляется раз в сутки)

Подсети российских государственных органов: Роскомнадзор, ФСБ, МВД и другие ведомства.  
Источник: [C24Be/AS_Network_List](https://github.com/C24Be/AS_Network_List) — ~1145 подсетей, ежедневное обновление.

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

## Установка GOVIPS (подсети госорганов РФ)

Отдельный ipset для блокировки RST от подсетей госорганов. Не пересекается с TSPUBLOCK.

```bash
# 1. Создать ipset и загрузить подсети
ipset create GOVIPS hash:net maxelem 65536
curl -s https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists_iptables/blacklist-v4.ipset \
  | grep "^add blacklist-v4 " \
  | sed 's/add blacklist-v4/add GOVIPS/' \
  | while read line; do ipset $line 2>/dev/null; done

# 2. Добавить правило iptables
iptables -N GOVBLOCK 2>/dev/null
iptables -I INPUT 1 -j GOVBLOCK
iptables -I GOVBLOCK -p tcp --tcp-flags RST RST -m set --match-set GOVIPS src -j DROP

# 3. Сохранить
ipset save > /etc/ipset.conf
netfilter-persistent save  # или: iptables-save > /etc/iptables/rules.v4

# 4. Скрипт автообновления
cat > /opt/update_govips.sh << 'EOF'
#!/bin/bash
URL="https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists_iptables/blacklist-v4.ipset"
curl -s "$URL" | grep "^add blacklist-v4 " | sed 's/add blacklist-v4/add GOVIPS/' | while read line; do
    ipset $line 2>/dev/null
done
ipset save > /etc/ipset.conf
echo "[$(date '+%Y-%m-%d %H:%M:%S')] GOVIPS обновлён: $(ipset list GOVIPS | grep 'Number of entries' | awk '{print $NF}') записей"
EOF
chmod +x /opt/update_govips.sh

# 5. Добавить в крон (4:00 ежедневно)
(crontab -l 2>/dev/null; echo "0 4 * * * /opt/update_govips.sh >> /var/log/govips.log 2>&1") | crontab -
```

## Отдельные списки

| Файл | Описание |
|---|---|
| [auto_collected.txt](https://github.com/upe4d/tspublock/blob/master/auto_collected.txt) | Автособранные RST IP — только RU, эксперимент, обновляется раз в сутки |
| Экспорт CyberOK | [iptables](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables&src=cyberok) · [MikroTik](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=mikrotik&src=cyberok) · [txt](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=txt&src=cyberok) |
| Экспорт полный | [iptables](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables) · [MikroTik](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=mikrotik) · [txt](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=txt) |
| GOVIPS (госорганы) | [ipset](https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists_iptables/blacklist-v4.ipset) · [txt](https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist-v4.txt) · via [C24Be/AS_Network_List](https://github.com/C24Be/AS_Network_List) |

> **Важно:** автосборные IP — экспериментальные. ТСПУ может подменять IP клиента, поэтому точность метода уточняется сообществом. Список обновляется раз в 3 дня.
>
> **Если нашли свой IP в списке** — удалите его через веб-интерфейс: откройте [stats.gptru.pro:4443/rst/](https://stats.gptru.pro:4443/rst/), найдите свой IP через поиск и нажмите кнопку ✕. Или командой на сервере:
> ```
> curl "https://stats.gptru.pro:4443/rst/api.php?action=delete&ip=ВАШ_IP"
> ```
> Сервер автоматически определяет ваш IP — удалить можно только свой.

## Экспорт списка

| Формат | CyberOK | Полный | GOVIPS (госорганы) |
|---|---|---|---|
| iptables/ipset | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables&src=cyberok) | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=iptables) | [скачать](https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists_iptables/blacklist-v4.ipset) |
| MikroTik .rsc | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=mikrotik&src=cyberok) | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=mikrotik) | — |
| Текст .txt | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=txt&src=cyberok) | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=txt) | [скачать](https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists/blacklist-v4.txt) |
| ipset restore | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=ipset&src=cyberok) | [скачать](https://stats.gptru.pro:4443/rst/api.php?action=export&fmt=ipset) | [скачать](https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists_iptables/blacklist-v4.ipset) |

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

## Как работает блокировка

Три независимых метода которые дополняют друг друга:

**1. Блокировка по IP (TSPUBLOCK)** — список известных адресов DPI оборудования из CyberOK Skipa + автосбор. Дропаем RST пакеты от этих IP.

**2. Блокировка госсетей (GOVIPS)** — подсети Роскомнадзора, ФСБ, МВД и других госорганов РФ. Источник: [C24Be/AS_Network_List](https://github.com/C24Be/AS_Network_List), обновляется ежедневно.

**3. Поведенческая блокировка (TSPUBLOCK2)** — дропаем RST которые пришли в течение 5 секунд после SYN. Не требует знать IP ТСПУ — блокирует по поведению. Поймал МегаФон (178.176.73.113) в первые минуты работы.

> Механизм до конца не изучен — ТСПУ может подменять IP клиента. Обсуждение продолжается в [@telemtrs](https://t.me/telemtrs).

## Состав репозитория

| Файл | Описание |
|---|---|
| `rst_collect.sh` | Автосбор RST IP — ставить на свой сервер в cron раз в сутки |
| `rst_submit.sh` | Сбор RST и отправка в нашу базу |
| `update_cyberok.sh` | Обновление списка CyberOK Skipa с GitHub |
| `api.php` | API: список IP, whois, статистика, экспорт |
| `collect.php` | Приёмник данных от участников |
| `index.html` | Веб-интерфейс |

## Связанные проекты

* [telemt-proxy-panel-bot-firewall](https://github.com/upe4d/telemt-proxy-panel-bot-firewall) — настройка telemt MTProxy
* [CyberOK_Skipa_ips](https://github.com/tread-lightly/CyberOK_Skipa_ips) — база сканеров ТСПУ
* [C24Be/AS_Network_List](https://github.com/C24Be/AS_Network_List) — подсети госорганов РФ (GOVIPS)
* [nikr-dev/mikrotik-adresslist-from-url](https://github.com/nikr-dev/mikrotik-adresslist-from-url) — автозагрузка в MikroTik
* Telegram канал: [@u_pre](https://t.me/u_pre)
