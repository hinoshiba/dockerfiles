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
test -z "${LOCAL_DOCKER_GID}" || groupmod -g "${LOCAL_DOCKER_GID}" docker
useradd -u $USER_ID -o -m ${LOCAL_WHOAMI}
groupmod -g $GROUP_ID ${LOCAL_WHOAMI}
passwd -d ${LOCAL_WHOAMI}
usermod -L ${LOCAL_WHOAMI}
gpasswd -a ${LOCAL_WHOAMI} docker
chown root:docker /var/run/docker.sock
chmod 660 /var/run/docker.sock
chown -R ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} /etc/dotfiles
echo "${LOCAL_WHOAMI} ALL=NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo

rm /home/${LOCAL_WHOAMI}/.bashrc || :
# built-in
chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} "${LOCAL_HOME}"
test "${LOCAL_HOME}" == "/home/${LOCAL_WHOAMI}" || (rm -rf "/home/${LOCAL_WHOAMI}" && ln -s "${LOCAL_HOME}" "/home/${LOCAL_WHOAMI}" && usermod -d "${LOCAL_HOME}" "${LOCAL_WHOAMI}")
sudo -u ${LOCAL_WHOAMI} cp /etc/dotfiles/bashrc /home/${LOCAL_WHOAMI}/.bashrc
sudo -u ${LOCAL_WHOAMI} echo "export LOCAL_HOSTNAME=${LOCAL_HOSTNAME}" >> /home/${LOCAL_WHOAMI}/.bashrc

test -n "${SSH_AUTH_SOCK:-}" && sudo -u ${LOCAL_WHOAMI} echo "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" >> /home/${LOCAL_WHOAMI}/.bashrc
test -n "${SSH_AUTH_SOCK:-}" && chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} "${SSH_AUTH_SOCK}"

mv /root/.cargo /home/${LOCAL_WHOAMI}/.cargo && chown -R ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} /home/${LOCAL_WHOAMI}/.cargo
mv /root/.rustup /home/${LOCAL_WHOAMI}/.rustup && chown -R ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} /home/${LOCAL_WHOAMI}/.rustup

ln -s /etc/dotfiles/vimrc /home/${LOCAL_WHOAMI}/.vimrc
cp -rf /var/dotfiles/.vim /home/${LOCAL_WHOAMI}/.vim && chown -R ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} /home/${LOCAL_WHOAMI}/.vim
ln -s /etc/dotfiles/screenrc /home/${LOCAL_WHOAMI}/.screenrc
ln -s /etc/dotfiles/selected_editor /home/${LOCAL_WHOAMI}/.selected_editor

test -d /home/${LOCAL_WHOAMI}/.host.ssh && ln -s /home/${LOCAL_WHOAMI}/.host.ssh /home/${LOCAL_WHOAMI}/.ssh

# shared directory
test -d /home/${LOCAL_WHOAMI}/.shared_cache/bash/ || sudo -u ${LOCAL_WHOAMI} mkdir -p /home/${LOCAL_WHOAMI}/.shared_cache/bash/
test -f /home/${LOCAL_WHOAMI}/.shared_cache/bash/bash_history || (sudo -u ${LOCAL_WHOAMI} touch /home/${LOCAL_WHOAMI}/.shared_cache/bash/bash_history && chmod 600 /home/${LOCAL_WHOAMI}/.shared_cache/bash/bash_history)
ln -s /home/${LOCAL_WHOAMI}/.shared_cache/bash/bash_history /home/${LOCAL_WHOAMI}/.bash_history

test -d /home/${LOCAL_WHOAMI}/.shared_cache/vim/ || sudo -u ${LOCAL_WHOAMI} mkdir -p /home/${LOCAL_WHOAMI}/.shared_cache/vim/
test -f /home/${LOCAL_WHOAMI}/.shared_cache/vim/viminfo || sudo -u ${LOCAL_WHOAMI} touch /home/${LOCAL_WHOAMI}/.shared_cache/vim/viminfo
ln -s /home/${LOCAL_WHOAMI}/.shared_cache/vim/viminfo /home/${LOCAL_WHOAMI}/.viminfo

test -d /home/${LOCAL_WHOAMI}/.shared_cache/.codex/ || sudo -u ${LOCAL_WHOAMI} mkdir -p /home/${LOCAL_WHOAMI}/.shared_cache/.codex/
ln -s /home/${LOCAL_WHOAMI}/.shared_cache/.codex /home/${LOCAL_WHOAMI}/.codex

test -d /home/${LOCAL_WHOAMI}/.shared_cache/screen-log/ || sudo -u ${LOCAL_WHOAMI}  mkdir -p /home/${LOCAL_WHOAMI}/.shared_cache/screen-log/

## permission
test -d /home/${LOCAL_WHOAMI}/.gnupg && chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} -R /home/${LOCAL_WHOAMI}/.gnupg || true
test -d /home/${LOCAL_WHOAMI}/.gnupg && find /home/${LOCAL_WHOAMI}/.gnupg -type d -exec chmod 700 {} \;
test -d /home/${LOCAL_WHOAMI}/.gnupg && find /home/${LOCAL_WHOAMI}/.gnupg -type f -exec chmod 600 {} \;

## configfile build
tgt="/home/${LOCAL_WHOAMI}/.muttrc"
test -f ${tgt}.add && (sudo -u ${LOCAL_WHOAMI} cp ${tgt}.add ${tgt} && sudo -u ${LOCAL_WHOAMI} cat /etc/dotfiles/muttrc >> ${tgt} && sudo -u ${LOCAL_WHOAMI} chmod 600 ${tgt})

tgt="/home/${LOCAL_WHOAMI}/.gitconfig"
test -f ${tgt}.add && (sudo -u ${LOCAL_WHOAMI} cp ${tgt}.add ${tgt} && sudo -u ${LOCAL_WHOAMI} chmod 600 ${tgt})
test -f ${tgt} && sudo -u ${LOCAL_WHOAMI} git config --global --add --bool push.autoSetupRemote true
test -f ${tgt} && sudo -u ${LOCAL_WHOAMI} git config --global url."git@github.com:".insteadOf "https://github.com/"

tgt="/home/${LOCAL_WHOAMI}/.screen_layout"
test -f ${tgt} || ln -s /etc/dotfiles/screen_layout /home/${LOCAL_WHOAMI}/.screen_layout

exec_usershell
