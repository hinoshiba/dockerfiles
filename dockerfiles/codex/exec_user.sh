#!/bin/bash
set -eu

CMD="codex"
if [ -n "$1" ]; then
	CMD="$1"
fi

function exec_usershell() {
	cd "${LOCAL_HOME}"
	exec sudo -u ${LOCAL_WHOAMI} ${CMD}
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

chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} "${LOCAL_HOME}"
test "${LOCAL_HOME}" == "/home/${LOCAL_WHOAMI}" || (rm -rf "/home/${LOCAL_WHOAMI}" && ln -s "${LOCAL_HOME}" "/home/${LOCAL_WHOAMI}" && usermod -d "${LOCAL_HOME}" "${LOCAL_WHOAMI}")

sudo -u ${LOCAL_WHOAMI} cp /etc/dotfiles/bashrc /home/${LOCAL_WHOAMI}/.bashrc
sudo -u ${LOCAL_WHOAMI} echo "export LOCAL_HOSTNAME=${LOCAL_HOSTNAME}" >> /home/${LOCAL_WHOAMI}/.bashrc

test -n "${SSH_AUTH_SOCK:-}" && sudo -u ${LOCAL_WHOAMI} echo "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" >> /home/${LOCAL_WHOAMI}/.bashrc
test -n "${SSH_AUTH_SOCK:-}" && chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} "${SSH_AUTH_SOCK}"
test -d /home/${LOCAL_WHOAMI}/.host.ssh && ln -s /home/${LOCAL_WHOAMI}/.host.ssh /home/${LOCAL_WHOAMI}/.ssh

test -d /home/${LOCAL_WHOAMI}/.shared_cache/.codex/ || sudo -u ${LOCAL_WHOAMI} mkdir -p /home/${LOCAL_WHOAMI}/.shared_cache/.codex/
ln -s /home/${LOCAL_WHOAMI}/.shared_cache/.codex /home/${LOCAL_WHOAMI}/.codex

exec_usershell
