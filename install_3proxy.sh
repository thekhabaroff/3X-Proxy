#!/bin/bash

# Скрипт автоматической установки и настройки 3proxy
# Использование: bash install_3proxy.sh

set -e

echo "=== Установка 3proxy ==="

# Проверка, что скрипт запущен от root
if [ "$EUID" -ne 0 ]; then 
    echo "Пожалуйста, запустите скрипт от root"
    exit 1
fi

# Запрос данных у пользователя
read -p "Введите IP адрес вашего VPS: " SERVER_IP
read -p "Введите логин для прокси: " PROXY_USER
read -sp "Введите пароль для прокси: " PROXY_PASS
echo
read -p "Введите порт для HTTP прокси (по умолчанию 3128): " HTTP_PORT
HTTP_PORT=${HTTP_PORT:-3128}
read -p "Введите порт для SOCKS прокси (по умолчанию 1080): " SOCKS_PORT
SOCKS_PORT=${SOCKS_PORT:-1080}

# Установка зависимостей
echo "Установка зависимостей..."
apt update
apt install build-essential wget -y

# Скачивание и компиляция 3proxy
echo "Скачивание 3proxy..."
cd /tmp
wget https://github.com/z3APA3A/3proxy/archive/0.9.5.tar.gz
tar xzf 0.9.5.tar.gz
cd 3proxy-0.9.5

echo "Компиляция 3proxy..."
make -f Makefile.Linux

# Создание пользователя
echo "Создание системного пользователя..."
if ! id proxy3 &>/dev/null; then
    adduser --system --no-create-home --disabled-login --group proxy3
fi

# Копирование файлов
echo "Установка 3proxy..."
mkdir -p /etc/3proxy /var/log/3proxy
cp bin/3proxy /usr/bin/
chown proxy3:proxy3 -R /etc/3proxy /var/log/3proxy /usr/bin/3proxy
chmod +x /usr/bin/3proxy

# Создание конфигурационного файла (ИСПРАВЛЕННАЯ ВЕРСИЯ)
echo "Создание конфигурации..."
cat > /etc/3proxy/3proxy.cfg <<EOF
pidfile /var/run/3proxy.pid

nserver 8.8.8.8
nscache 65536

timeouts 1 5 30 60 180 1800 15 60

log /var/log/3proxy/3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %I %h %T"

auth strong
users ${PROXY_USER}:CL:${PROXY_PASS}
allow ${PROXY_USER}

proxy -p${HTTP_PORT} -i${SERVER_IP} -e${SERVER_IP}
socks -p${SOCKS_PORT} -i${SERVER_IP} -e${SERVER_IP}
EOF

# Создание systemd службы
echo "Создание systemd службы..."
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/3proxy /etc/3proxy/3proxy.cfg
ExecStop=/bin/killall 3proxy
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Запуск службы
echo "Запуск 3proxy..."
systemctl daemon-reload
systemctl enable 3proxy
systemctl start 3proxy

# Проверка статуса
sleep 2
if systemctl is-active --quiet 3proxy; then
    echo ""
    echo "=== Установка завершена успешно! ==="
    echo ""
    echo "HTTP прокси: ${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:${HTTP_PORT}"
    echo "SOCKS прокси: ${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:${SOCKS_PORT}"
    echo ""
    echo "Проверка работы:"
    echo "curl -x ${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:${HTTP_PORT} https://ifconfig.me"
    echo ""
    echo "Конфигурация: /etc/3proxy/3proxy.cfg"
    echo "Логи: /var/log/3proxy/3proxy.log"
    echo "Управление: systemctl {start|stop|restart|status} 3proxy"
else
    echo ""
    echo "=== ОШИБКА: служба не запустилась ==="
    echo "Проверьте логи: journalctl -u 3proxy -n 50"
    exit 1
fi
