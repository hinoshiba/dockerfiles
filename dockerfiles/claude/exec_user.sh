#!/bin/bash
set -eu

CMD="claude"
if [ -n "$1" ]; then
	CMD="$1"
fi

function exec_usershell() {
	echo "----------------------------"
	sudo -u ${LOCAL_WHOAMI} cat /home/${LOCAL_WHOAMI}/.bashrc
	echo "----------------------------"
	sudo -u ${LOCAL_WHOAMI} cat /home/${LOCAL_WHOAMI}/.profile
	echo "----------------------------"
	sudo -u ${LOCAL_WHOAMI} ls -lah /home/${LOCAL_WHOAMI}/.local/bin
	echo "----------------------------"
	sudo -iu ${LOCAL_WHOAMI} cd ~/ && pwd
	echo "----------------------------"
	sudo -iu ${LOCAL_WHOAMI} cat ~/.bashrc
	echo "----------------------------"
	sudo -iu ${LOCAL_WHOAMI} cat ~/.profile
	echo "----------------------------"
	cd "${WORK_DIR}"
	exec sudo -iu ${LOCAL_WHOAMI} ${CMD}
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
echo "${LOCAL_WHOAMI} ALL=NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo

test -n "${SSH_AUTH_SOCK:-}" && sudo -u ${LOCAL_WHOAMI} echo "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" >> /home/${LOCAL_WHOAMI}/.bashrc
test -n "${SSH_AUTH_SOCK:-}" && chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} "${SSH_AUTH_SOCK}"
test -d /home/${LOCAL_WHOAMI}/.host.ssh && ln -s /home/${LOCAL_WHOAMI}/.host.ssh /home/${LOCAL_WHOAMI}/.ssh

echo "Calude installing"
sudo -iu ${LOCAL_WHOAMI} `curl -fsSL https://claude.ai/install.sh | bash`
echo "Calude installed"
sudo -iu ${LOCAL_WHOAMI} echo 'export PATH="${HOME}/.local/bin:$PATH"' >> /home/${LOCAL_WHOAMI}/.bashrc
sudo -iu ${LOCAL_WHOAMI} echo 'export PATH="${HOME}/.local/bin:$PATH"' >> /home/${LOCAL_WHOAMI}/.profile

exec_usershell
