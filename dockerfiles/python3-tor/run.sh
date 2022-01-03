#!/bin/bash

service tor start || exit 1
curl -x socks5h://0:9150 http://ipinfo.io || exit 1

echo "connected!!"
echo 'USAGE: open "/Applications/<browser>.app" --args --proxy-server="socks5://localhost:9150'
echo 'USAGE: curl -x socks5h://0:9150 <target url>'
