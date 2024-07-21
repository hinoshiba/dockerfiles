#!/bin/bash

CRED_SRC="${HOME}/.docker.credential.gpg"
CONFIG="${HOME}/.docker/config.json"

mkdir -p ${HOME}/.docker
test -f ${CONFIG} && exec docker "$@"
test -f ${CRED_SRC} || exec docker "$@"
test -z ${CRED_SRC} && exec docker "$@"

echo "{\"auths\":{\"https://index.docker.io/v1/\":{\"auth\":\"$(gpg -d ${CRED_SRC}|base64)\"}}}" > ${CONFIG}
exec docker "$@"
