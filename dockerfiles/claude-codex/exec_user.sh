#!/bin/bash
set -eu

if [ "$#" -eq 0 ]; then
	set -- /bin/bash
fi

function update_startup_tools() {
	command -v npm > /dev/null || {
		echo "ERROR: npm not found; cannot update codex" >&2
		exit 1
	}
	echo "Updating codex..."
	npm install -g @openai/codex@latest
	hash -r

	echo "Updating claude..."
	sudo -iu "${LOCAL_WHOAMI}" bash -c "curl -fsSL https://claude.ai/install.sh | bash"
	for profile in /home/${LOCAL_WHOAMI}/.bashrc /home/${LOCAL_WHOAMI}/.profile; do
		grep -qxF 'export PATH="${HOME}/.local/bin:$PATH"' "${profile}" || \
			echo 'export PATH="${HOME}/.local/bin:$PATH"' >> "${profile}"
	done

	echo "Setting up standard skills (claude/codex plugins)..."
	sudo -iu "${LOCAL_WHOAMI}" env \
		HOME="/home/${LOCAL_WHOAMI}" \
		SKILLS_BOOTSTRAP="${SKILLS_BOOTSTRAP:-}" \
		SKILLS_REFRESH="${SKILLS_REFRESH:-}" \
		bash /usr/local/bin/setup_skills.sh || true
}

function exec_usershell() {
	cd "${WORK_DIR}"
	exec sudo -H -u "${LOCAL_WHOAMI}" env \
		HOME="/home/${LOCAL_WHOAMI}" \
		USER="${LOCAL_WHOAMI}" \
		LOGNAME="${LOCAL_WHOAMI}" \
		PATH="/home/${LOCAL_WHOAMI}/.local/bin:${PATH}" \
		bash -c 'cd "$1" || exit 1; shift; exec "$@"' bash "${WORK_DIR}" "$@"
}

function notice_codex_setup() {
	# Show a reminder to finish wiring cc-plugin-codex inside Codex.
	# Only relevant when launching Codex, only while the one-time step is pending.
	local cmd="${1:-}"
	if [ "${cmd}" != "codex" ]; then
		return 0
	fi

	local codex_home="/home/${LOCAL_WHOAMI}/.codex"
	if [ ! -f "${codex_home}/.cc-plugin-codex.bootstrap" ]; then
		return 0
	fi
	if [ -f "${codex_home}/.cc-plugin-codex.ready" ]; then
		return 0
	fi

	cat <<'EOF'

============================================================
 [skills] cc-plugin-codex (Codex -> Claude Code) is installed.

   One-time step: run   $cc:setup   inside Codex to finish wiring.
   After that you can use:  $cc:review  $cc:rescue  $cc:status ...

   To silence this reminder once done:
     touch ~/.codex/.cc-plugin-codex.ready
============================================================

EOF
}

USER_ID=${LOCAL_UID:-9001}
GROUP_ID=${LOCAL_GID:-9001}

if ! getent passwd ${LOCAL_WHOAMI} > /dev/null; then
	echo "Starting with UID : $USER_ID, GID: $GROUP_ID"
	test -z "${LOCAL_DOCKER_GID}" || groupmod -g "${LOCAL_DOCKER_GID}" docker
	useradd -u $USER_ID -o -m ${LOCAL_WHOAMI}
	groupmod -g $GROUP_ID ${LOCAL_WHOAMI}
	passwd -d ${LOCAL_WHOAMI}
	usermod -L ${LOCAL_WHOAMI}
	gpasswd -a ${LOCAL_WHOAMI} docker
	echo "${LOCAL_WHOAMI} ALL=NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo
fi

if [ -S /var/run/docker.sock ]; then
	chown root:docker /var/run/docker.sock
	chmod 660 /var/run/docker.sock
fi

test -n "${SSH_AUTH_SOCK:-}" && grep -qxF "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" /home/${LOCAL_WHOAMI}/.bashrc || \
	test -z "${SSH_AUTH_SOCK:-}" || sudo -u ${LOCAL_WHOAMI} echo "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" >> /home/${LOCAL_WHOAMI}/.bashrc
test -n "${SSH_AUTH_SOCK:-}" && chown ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} "${SSH_AUTH_SOCK}"
test -d /home/${LOCAL_WHOAMI}/.host.ssh && test ! -e /home/${LOCAL_WHOAMI}/.ssh && ln -s /home/${LOCAL_WHOAMI}/.host.ssh /home/${LOCAL_WHOAMI}/.ssh

chown -R ${LOCAL_WHOAMI}:${LOCAL_WHOAMI} /home/${LOCAL_WHOAMI} || :
update_startup_tools

notice_codex_setup "$@"
exec_usershell "$@"
