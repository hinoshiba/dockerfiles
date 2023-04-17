#!/bin/bash
set -eu

SHELL="/bin/bash"
DOCKERFILE_PATH="${HOME}/git/github.com/hinoshiba/dockerfiles"
DIR=$(pwd)

if [ $# -ne 1 ]; then
	echo "usage: work.sh <target>"
fi

target="${1}"

cd "${DOCKERFILE_PATH}" && make target=${target}
make stop target=${target} || :
cd "${DIR}"
