#!/bin/bash

USER_ID=${LOCAL_UID:-9001}
GROUP_ID=${LOCAL_GID:-9001}

echo "Starting with UID : $USER_ID, GID: $GROUP_ID"
useradd -u $USER_ID -o -m ${LOCAL_WHOAMI}
groupmod -g $GROUP_ID ${LOCAL_WHOAMI}

ln -s /mnt/${LOCAL_HOME}/.bashrc /home/${LOCAL_WHOAMI}/.bashrc
ln -s /mnt/${LOCAL_HOME}/.vimrc /home/${LOCAL_WHOAMI}/.vimrc
ln -s /mnt/${LOCAL_HOME}/.ssh /home/${LOCAL_WHOAMI}/.ssh
ln -s /mnt/${LOCAL_HOME}/.screenrc /home/${LOCAL_WHOAMI}/.screenrc
ln -s /mnt/${LOCAL_HOME}/Downloads /home/${LOCAL_WHOAMI}/Downloads

exec su -l -s /bin/bash - ${LOCAL_WHOAMI}
