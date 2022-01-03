#!/bin/bash

service tor start
curl -x socks5h://0:9150 http://ipinfo.io
