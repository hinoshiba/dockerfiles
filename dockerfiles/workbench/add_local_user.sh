#!/bin/bash

USER_ID=${LOCAL_UID:-9001}
GROUP_ID=${LOCAL_GID:-9001}

echo "Starting with UID : $USER_ID, GID: $GROUP_ID"
useradd -u $USER_ID -o -m wrkkk
groupmod -g $GROUP_ID wrkkk

cat <<EOL >> /home/wrkkk/.bashrc
export SHELL=/bin/bash
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8
export HOME=${LOCAL_HOME}
EOL

su - -l wrkkk
#su - -l wrkkk "$@"
