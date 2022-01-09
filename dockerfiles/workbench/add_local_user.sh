#!/bin/bash

USER_ID=${LOCAL_UID:-9001}
GROUP_ID=${LOCAL_GID:-9001}

echo "Starting with UID : $USER_ID, GID: $GROUP_ID"
useradd -u $USER_ID -o -m ${LOCAL_WHOAMI}
groupmod -g $GROUP_ID ${LOCAL_WHOAMI}
passwd -d ${LOCAL_WHOAMI}
#usermod -L ${LOCAL_WHOAMI}
chown -R ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} /etc/dotfiles
echo "${LOCAL_WHOAMI} ALL=NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo

rm /home/${LOCAL_WHOAMI}/.bashrc
# built-in
ln -s /etc/dotfiles/bashrc /home/${LOCAL_WHOAMI}/.bashrc
ln -s /etc/dotfiles/vimrc /home/${LOCAL_WHOAMI}/.vimrc
ln -s /etc/dotfiles/screenrc /home/${LOCAL_WHOAMI}/.screenrc
ln -s /etc/dotfiles/newsboat /home/${LOCAL_WHOAMI}/.newsboat
ln -s /etc/dotfiles/selected_editor /home/${LOCAL_WHOAMI}/.selected_editor

# mount:ro
ln -s /mnt/${LOCAL_HOME}/.ssh /home/${LOCAL_WHOAMI}/.ssh
ln -s /mnt/${LOCAL_HOME}/.gnupg /home/${LOCAL_WHOAMI}/.gnupg
ln -s /mnt/${LOCAL_HOME}/.gitconfig /home/${LOCAL_WHOAMI}/.gitconfig
ln -s /mnt/${LOCAL_HOME}/Downloads /home/${LOCAL_WHOAMI}/Downloads

# mount:wr
ln -s /mnt/${LOCAL_HOME}/work /home/${LOCAL_WHOAMI}/work
ln -s /mnt/${LOCAL_HOME}/shared_cache /home/${LOCAL_WHOAMI}/shared_cache

# shared directory
sudo -u ${LOCAL_WHOAMI} test -d /home/${LOCAL_WHOAMI}/shared_cache/newsboat/ || mkdir -p /home/${LOCAL_WHOAMI}/shared_cache/newsboat/
sudo -u ${LOCAL_WHOAMI} test -f /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db || touch /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db
sudo -u ${LOCAL_WHOAMI} test -f /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db.lock || touch /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db.lock
ln -s /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db /home/${LOCAL_WHOAMI}/.newsboat/cache.db
ln -s /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db.lock /home/${LOCAL_WHOAMI}/.newsboat/cache.db.lock

sudo -u ${LOCAL_WHOAMI} test -d /home/${LOCAL_WHOAMI}/shared_cache/screen-log/ || mkdir -p /home/${LOCAL_WHOAMI}/shared_cache/screen-log/

su -l -s /bin/bash - ${LOCAL_WHOAMI}
