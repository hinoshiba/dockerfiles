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

cp ${TEMPLATES}/${target}/Makefile ./

case "${target}" in
	python)
		echo "__pycache__/** " >> .gitignore
		;;
esac

cd "${DIR}"
