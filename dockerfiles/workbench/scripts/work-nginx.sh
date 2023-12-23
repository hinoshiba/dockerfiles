#!/bin/bash
set -eu

SHELL="/bin/bash"
DOCKERFILE_PATH="${HOME}/git/github.com/hinoshiba/dockerfiles"
DIR=$(pwd)

target="nginx"

if [[ "$(pwd)" =~ "${HOME}/git/".*$ ]]; then
	cd "${DOCKERFILE_PATH}" && make target=${target} mount=${HOME}/git workdir="${DIR}" port=80 root=y
else
	cd "${DOCKERFILE_PATH}" && make target=${target} mount=${HOME}/git port=80 root=y
fi
make stop target=${target} || :
cd "${DIR}"
