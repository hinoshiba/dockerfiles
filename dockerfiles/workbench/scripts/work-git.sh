#!/bin/bash
set -eu

SHELL="/bin/bash"
DOCKERFILE_PATH="${HOME}/git/github.com/hinoshiba/dockerfiles"
DIR=$(pwd)

if [ $# -ne 1 ]; then
	echo "usage: work.sh <target>"
	exit 1
fi

target="${1}"

if [[ "$(pwd)" =~ "${HOME}/git/".*$ ]]; then
	cd "${DOCKERFILE_PATH}" && make target=${target} mount=${HOME}/git workdir="${DIR}"
else
	cd "${DOCKERFILE_PATH}" && make target=${target} mount=${HOME}/git
fi
make stop target=${target} || :
cd "${DIR}"
