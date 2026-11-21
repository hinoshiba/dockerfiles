#!/bin/bash
set -eu

# Explicit root mode still receives the shared directories and agent forwarding.
if [ "${WORKBENCH_ROOT:-}" = 1 ]; then
    [ "$#" -gt 0 ] || set -- /bin/bash
    if [ "$1" = /usr/local/bin/exec_user.sh ]; then shift; fi
    [ "$#" -gt 0 ] || set -- /bin/bash
    exec "$@"
fi

LOCAL_WHOAMI=${LOCAL_WHOAMI:-workbench}
LOCAL_HOME=${LOCAL_HOME:-/home/${LOCAL_WHOAMI}}
LOCAL_HOSTNAME=${LOCAL_HOSTNAME:-container}
PATH_DOCKERFILES=${PATH_DOCKERFILES:-${LOCAL_HOME}/git/github.com/hinoshiba/dockerfiles}
USER_ID=${LOCAL_UID:-9001}
GROUP_ID=${LOCAL_GID:-9001}

# A second `make`/exec may arrive while the first shell is initializing its home.
exec 9>/run/workbench-setup.lock
flock 9

exec_usershell() {
    cd "${LOCAL_HOME}"
    if [ "${1:-}" = /usr/local/bin/exec_user.sh ]; then shift; fi
    [ "$#" -gt 0 ] || set -- /bin/bash
    flock -u 9
    exec 9>&-
    exec sudo -H -u "${LOCAL_WHOAMI}" env \
        HOME="${LOCAL_HOME}" USER="${LOCAL_WHOAMI}" LOGNAME="${LOCAL_WHOAMI}" \
        SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}" \
        DOCKERFILES_DOCKER_SSH_SOCK="${DOCKERFILES_DOCKER_SSH_SOCK:-}" \
        PATH="${LOCAL_HOME}/.cargo/bin:/usr/local/go/bin:${PATH}" \
        PATH_DOCKERFILES="${PATH_DOCKERFILES}" "$@"
}

if getent passwd "${LOCAL_WHOAMI}" >/dev/null; then
    exec_usershell "$@"
fi

printf 'Starting with UID: %s, GID: %s\n' "$USER_ID" "$GROUP_ID"
getent group docker >/dev/null || groupadd docker
if [ -n "${LOCAL_DOCKER_GID:-}" ]; then
    groupmod -g "${LOCAL_DOCKER_GID}" docker
fi
useradd -u "$USER_ID" -o -m "${LOCAL_WHOAMI}"
groupmod -g "$GROUP_ID" "${LOCAL_WHOAMI}"
passwd -d "${LOCAL_WHOAMI}"
usermod -L "${LOCAL_WHOAMI}"
gpasswd -a "${LOCAL_WHOAMI}" docker
if [ -S /var/run/docker.sock ]; then
    chown root:docker /var/run/docker.sock
    chmod 660 /var/run/docker.sock
elif [ "${DOCKER_SOCKET_DISABLED:-}" != 1 ]; then
    echo 'ERROR: Docker socket is missing; use docker_socket=n only to explicitly disable Docker integration.' >&2
    exit 1
fi
chown -R "${LOCAL_WHOAMI}:${LOCAL_WHOAMI}" /etc/dotfiles
printf '%s ALL=NOPASSWD: ALL\n' "${LOCAL_WHOAMI}" > "/etc/sudoers.d/workbench-user"
chmod 440 /etc/sudoers.d/workbench-user

mkdir -p "${LOCAL_HOME}"
chown "${LOCAL_WHOAMI}:${LOCAL_WHOAMI}" "${LOCAL_HOME}"
if [ "${LOCAL_HOME}" != "/home/${LOCAL_WHOAMI}" ]; then
    rm -rf "/home/${LOCAL_WHOAMI}"
    ln -s "${LOCAL_HOME}" "/home/${LOCAL_WHOAMI}"
    usermod -d "${LOCAL_HOME}" "${LOCAL_WHOAMI}"
fi
sudo -u "${LOCAL_WHOAMI}" cp /etc/dotfiles/bashrc "${LOCAL_HOME}/.bashrc"
{
    printf 'export LOCAL_HOSTNAME=%q\n' "${LOCAL_HOSTNAME}"
    printf 'export PATH_DOCKERFILES=%q\n' "${PATH_DOCKERFILES}"
    if [ -n "${SSH_AUTH_SOCK:-}" ]; then printf 'export SSH_AUTH_SOCK=%q\n' "${SSH_AUTH_SOCK}"; fi
    if [ -n "${DOCKERFILES_DOCKER_SSH_SOCK:-}" ]; then printf 'export DOCKERFILES_DOCKER_SSH_SOCK=%q\n' "${DOCKERFILES_DOCKER_SSH_SOCK}"; fi
} >> "${LOCAL_HOME}/.bashrc"
for socket in "${SSH_AUTH_SOCK:-}" "${SSH_AGENT_ALIAS:-}"; do
    if [ -n "$socket" ] && [ -S "$socket" ]; then
        chown "${LOCAL_WHOAMI}:${LOCAL_WHOAMI}" "$socket"
        if [ "${DOCKERFILES_ENGINE:-}" = apple ]; then chmod 600 "$socket"; fi
        # Apple creates socket-only parent directories as root/0700. Give the
        # user access to guest-created parents, never chmod a shared host tree.
        parent=$(dirname "$socket")
        while [ "${DOCKERFILES_ENGINE:-}" = apple ] && [[ "$parent" == "${LOCAL_HOME}/"* ]]; do
            if [ "$(findmnt -n -o FSTYPE -T "$parent")" != virtiofs ]; then
                chown "${LOCAL_WHOAMI}:${LOCAL_WHOAMI}" "$parent"
                chmod u+rwx "$parent"
            fi
            parent=$(dirname "$parent")
        done
    fi
done

for directory in .cargo .rustup; do
    mv "/root/${directory}" "${LOCAL_HOME}/${directory}"
    chown -R "${LOCAL_WHOAMI}:${LOCAL_WHOAMI}" "${LOCAL_HOME}/${directory}"
done
for name in vimrc screenrc selected_editor gitignore_global; do
    ln -sf "/etc/dotfiles/${name}" "${LOCAL_HOME}/.${name}"
done
cp -r /var/dotfiles/.vim "${LOCAL_HOME}/.vim"
chown -R "${LOCAL_WHOAMI}:${LOCAL_WHOAMI}" "${LOCAL_HOME}/.vim"
if [ -d "${LOCAL_HOME}/.host.ssh" ]; then
    ln -s "${LOCAL_HOME}/.host.ssh" "${LOCAL_HOME}/.ssh"
fi

for directory in bash vim screen-log; do
    sudo -u "${LOCAL_WHOAMI}" mkdir -p "${LOCAL_HOME}/.shared_cache/${directory}"
done
sudo -u "${LOCAL_WHOAMI}" touch "${LOCAL_HOME}/.shared_cache/bash/bash_history" "${LOCAL_HOME}/.shared_cache/vim/viminfo"
chmod 600 "${LOCAL_HOME}/.shared_cache/bash/bash_history"
ln -s "${LOCAL_HOME}/.shared_cache/bash/bash_history" "${LOCAL_HOME}/.bash_history"
ln -s "${LOCAL_HOME}/.shared_cache/vim/viminfo" "${LOCAL_HOME}/.viminfo"

# Only change the guest-created GPG directory. Mounted keys/keyrings are RO;
# chmod/chown on those may fail or alter host permissions through file sharing.
if [ -d "${LOCAL_HOME}/.gnupg" ]; then
    chown "${LOCAL_WHOAMI}:${LOCAL_WHOAMI}" "${LOCAL_HOME}/.gnupg"
    chmod 700 "${LOCAL_HOME}/.gnupg"
fi
if [ -f "${LOCAL_HOME}/.gitconfig.add" ]; then
    sudo -u "${LOCAL_WHOAMI}" cp "${LOCAL_HOME}/.gitconfig.add" "${LOCAL_HOME}/.gitconfig"
    sudo -u "${LOCAL_WHOAMI}" chmod 600 "${LOCAL_HOME}/.gitconfig"
    sudo -H -u "${LOCAL_WHOAMI}" git config --global --add --bool push.autoSetupRemote true
    sudo -H -u "${LOCAL_WHOAMI}" git config --global url."git@github.com:".insteadOf "https://github.com/"
    sudo -H -u "${LOCAL_WHOAMI}" git config --global core.excludesfile "${LOCAL_HOME}/.gitignore_global"
fi
if [ ! -f "${LOCAL_HOME}/.screen_layout" ]; then
    ln -s /etc/dotfiles/screen_layout "${LOCAL_HOME}/.screen_layout"
fi
exec_usershell "$@"
