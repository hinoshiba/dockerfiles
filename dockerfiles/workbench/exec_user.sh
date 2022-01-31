#!/bin/bash
set -eu

function exec_usershell() {
	cd "${LOCAL_HOME}"
	exec sudo -u ${LOCAL_WHOAMI} /bin/bash
}

USER_ID=${LOCAL_UID:-9001}
GROUP_ID=${LOCAL_GID:-9001}

getent passwd ${LOCAL_WHOAMI} > /dev/null && exec_usershell

echo "Starting with UID : $USER_ID, GID: $GROUP_ID"
useradd -u $USER_ID -o -m ${LOCAL_WHOAMI}
groupmod -g $GROUP_ID ${LOCAL_WHOAMI}
passwd -d ${LOCAL_WHOAMI}
usermod -L ${LOCAL_WHOAMI}
gpasswd -a ${LOCAL_WHOAMI} docker
chown root:docker /var/run/docker.sock
chmod 660 /var/run/docker.sock
chown -R ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} /etc/dotfiles
echo "${LOCAL_WHOAMI} ALL=NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo

rm /home/${LOCAL_WHOAMI}/.bashrc || true
# built-in
chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} "${LOCAL_HOME}"
test "${LOCAL_HOME}" == "/home/${LOCAL_WHOAMI}" || (rm -rf "/home/${LOCAL_WHOAMI}" && ln -s "${LOCAL_HOME}" "/home/${LOCAL_WHOAMI}" && usermod -d "${LOCAL_HOME}" "${LOCAL_WHOAMI}")
sudo -u ${LOCAL_WHOAMI} cp /etc/dotfiles/bashrc /home/${LOCAL_WHOAMI}/.bashrc
sudo -u ${LOCAL_WHOAMI} echo "export LOCAL_HOSTNAME=${LOCAL_HOSTNAME}" >> /home/${LOCAL_WHOAMI}/.bashrc

ln -s /etc/dotfiles/vimrc /home/${LOCAL_WHOAMI}/.vimrc
ln -s /etc/dotfiles/screenrc /home/${LOCAL_WHOAMI}/.screenrc
ln -s /etc/dotfiles/newsboat /home/${LOCAL_WHOAMI}/.newsboat
ln -s /etc/dotfiles/selected_editor /home/${LOCAL_WHOAMI}/.selected_editor

# shared directory
test -d /home/${LOCAL_WHOAMI}/shared_cache/newsboat/ || sudo -u ${LOCAL_WHOAMI} mkdir -p /home/${LOCAL_WHOAMI}/shared_cache/newsboat/
test -f /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db || sudo -u ${LOCAL_WHOAMI} touch /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db
test -f /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db.lock || sudo -u ${LOCAL_WHOAMI} touch /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db.lock
ln -s /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db /home/${LOCAL_WHOAMI}/.newsboat/cache.db
ln -s /home/${LOCAL_WHOAMI}/shared_cache/newsboat/cache.db.lock /home/${LOCAL_WHOAMI}/.newsboat/cache.db.lock

test -d /home/${LOCAL_WHOAMI}/shared_cache/screen-log/ || sudo -u ${LOCAL_WHOAMI}  mkdir -p /home/${LOCAL_WHOAMI}/shared_cache/screen-log/

## permission
chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} -R /home/${LOCAL_WHOAMI}/.gnupg || true
find /home/${LOCAL_WHOAMI}/.gnupg -type d -exec chmod 700 {} \;
find /home/${LOCAL_WHOAMI}/.gnupg -type f -exec chmod 600 {} \;

## configfile build
test -f /home/${LOCAL_WHOAMI}/.muttrc || (sudo -u ${LOCAL_WHOAMI} cp /home/${LOCAL_WHOAMI}/.muttrc.add /home/${LOCAL_WHOAMI}/.muttrc && sudo -u ${LOCAL_WHOAMI} cat /etc/dotfiles/muttrc >> /home/${LOCAL_WHOAMI}/.muttrc && sudo -u ${LOCAL_WHOAMI} chmod 600 /home/${LOCAL_WHOAMI}/.muttrc)

exec_usershell
