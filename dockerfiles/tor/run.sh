#!/bin/bash
set -ue

sleep 1
service tor start || exit 1
echo "[[[Network Infomation]]]"
curl -s -x socks5h://0:9150 http://ipinfo.io || exit 1
echo "[[[Info]]]"
echo "socks5: :9150"
echo "dnsport: :8853"

if [ $# -eq 1 ]; then
	${1}
fi

exec /bin/bash
