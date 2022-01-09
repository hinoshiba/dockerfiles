#!/bin/bash

USER_ID=${LOCAL_UID:-9001}
GROUP_ID=${LOCAL_GID:-9001}

echo "Starting with UID : $USER_ID, GID: $GROUP_ID"
useradd -u $USER_ID -o -m ${LOCAL_WHOAMI}
groupmod -g $GROUP_ID ${LOCAL_WHOAMI}
rm -rf /home/${LOCAL_WHOAMI}
ln -s ${LOCAL_HOME} /home/${LOCAL_WHOAMI}

#cat <<EOL >> /home/${LOCAL_WHOAMI}/.bashrc
#export SHELL=/bin/bash
#export LANG=ja_JP.UTF-8
#export LC_ALL=ja_JP.UTF-8
#EOL

exec su -l -s /bin/bash - ${LOCAL_WHOAMI}
#su - -l wrkkk "$@"
