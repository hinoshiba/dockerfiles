# Export values instead of interpolating them into shell code (spaces are safe).
.DEFAULT_GOAL := all
PYTHON ?= python3
engine ?= auto
auto_install ?= y
export DF_REPO := $(CURDIR)
# `value` avoids Make interpreting dollar expressions intended for the guest
# shell (or literal dollar characters in paths and AI command arguments).
export DF_ENGINE = $(value engine)
export DF_AUTO_INSTALL = $(value auto_install)
export DF_TARGET = $(value target)
export DF_TAG = $(value tag)
export DF_MOUNT = $(value mount)
export DF_ROOT = $(value root)
export DF_AUTORM = $(value autorm)
export DF_CREATER = $(if $(value creater),$(value creater),$(value builder))
export DF_PORT = $(value port)
export DF_CNAME = $(value cname)
export DF_DAEMON = $(value daemon)
export DF_CMD = $(value cmd)
export DF_AUTOREBUILD = $(value autorebuild)
export DF_NOCACHE = $(value nocache)
export DF_WORK_DIR = $(if $(value work_dir),$(value work_dir),$(value workdir))
export DF_LOCALIMG = $(value localimg)
export DF_ARGS = $(value ARGS)
export DF_CODEX_CMD = $(value CODEX_CMD)
export DF_CLAUDE_CMD = $(value CLAUDE_CMD)
export DF_SSH_AGENT = $(value ssh_agent)
export DF_DOCKER_SOCKET = $(value docker_socket)
export DF_DOCKER_SSH_AGENT = $(value docker_ssh_agent)
export CONTAINER_MEMORY
export CONTAINER_BUILD_MEMORY

.PHONY: all build pull start test install uninstall attach stop clean allclean allrm allrmi allrmo check_health check_target help check repopull are_you_sure

all build pull start test install uninstall attach stop clean allrm allrmi allrmo check_health check_target:
	@$(PYTHON) scripts/launch.py $@

allclean: are_you_sure
	@$(PYTHON) scripts/launch.py allclean

# The former Docker system-prune command prompted before deleting volumes.
allrmo: are_you_sure

are_you_sure:
	@printf 'Are you sure? [y/N]: '; read -r answer && test "$$answer" = y

repopull:
	git pull

check:
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v
	@bash -n dockerfiles/workbench/exec_user.sh dockerfiles/claude-codex/exec_user.sh dockerfiles/claude-codex/setup_skills.sh dockerfiles/claude-codex/setup_ecc.sh tests/workbench-image-smoke.sh tests/composite-image-smoke.sh tests/node-image-smoke.sh

help:
	@printf '%s\n' \
	  'make [all|start|build|pull|attach|stop|test|clean] target=<image>' \
	  '  engine=auto|apple|docker   auto: Apple silicon/macOS 26+, otherwise Docker' \
	  '  auto_install=n           Disable automatic installation of missing engines' \
	  '  localimg=y tag=<tag> creater=<name> cname=<name> cmd="command args"' \
	  '  root=y daemon=n autorm=n mount=<path> work_dir=<path> port=<port>' \
	  '  ssh_agent=<socket> docker_socket=<socket|n> ARGS="AI arguments"' \
	  '  docker_ssh_agent=<path>   SSH agent source visible to nested Docker daemon' \
	  'make install / check / help; see docs/options.md and docs/container-runtimes.md'
