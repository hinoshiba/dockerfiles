#!/bin/bash
set -eu

SHELL="/bin/bash"
TEMPLATES=/usr/local/src/templates
DIR=$(pwd)

if [ $# -ne 1 ]; then
	echo "usage: template.sh <target>"
	exit 1
fi

target="${1}"

cp -i ${TEMPLATES}/${target}/Makefile ./

case "${target}" in
	python)
		echo "__pycache__/** " >> .gitignore
		;;
	go)
		echo "bin/" >> .gitignore
		echo "vendor/" >> .gitignore
		echo "go.sum" >> .gitignore
		;;
esac

cd "${DIR}"
