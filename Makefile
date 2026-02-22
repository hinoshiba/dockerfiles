# mydocker makefile@hinoshiba:##
#  usage: ## make [target=<targetpath>] [tag=<tag>] [root=y] [daemon=n] [autorm=n] [mount=<path>] [creater=<name>] [port=<number>] [cname=<container name>] [cmd=<exec command>] [autorebuild=n] [nocache=n] [work_dir=<work dir>] [localimg=y]
#  sample: ## make target=golang root=y autorm=n daemon=n mount=/home/hinoshiba/Downloads creater=hinoshiba port=80 cname=run02
#  sample: ## make target=tor gui=firefox
#  =======options========  :##
## You can add text at help menu, pattern of '#<string>: <string2>'

## const
DEFAULT_CMD=/bin/bash
D=docker
SP_WORKBENCH=workbench
SP_CODEX=codex
SP_CLAUDE=claude
PATH_MTX=.mtx/
DEFAULT_BUILDER=hinoshiba

## args
TGT=${target}
TAG=${tag}
MOUNT=${mount}
ROOT=${root}
AUTORM=${autorm}
CREATER=${creater}
PORT=${port}
C_NAME=${cname}
DAEMON=${daemon}
GUI=${gui}
CMD=${cmd}
AUTOREBUILD=${autorebuild}
NOCACHE=${nocache}
WORK_DIR=${work_dir}
USE_LOCALIMG=${localimg}
LOCAL_UID=$(shell id -u)
LOCAL_GID=$(shell id -g)
LOCAL_GID_MAC=$(LOCAL_UID)
LOCAL_WHOAMI=$(shell id -un)
LOCAL_GROUP=$(shell id -gn)
LOCAL_DOCKER_GID=$(shell getent group docker | awk  -F: '{print $$3}')
LOCAL_HOME=$(HOME)
ifeq ($(WORK_DIR),)
WORK_DIR=$(shell pwd)
endif
LOCAL_HOSTNAME=$(shell hostname)

## import
TGT_SRCS=$(shell find ./dockerfiles/$(TGT) -type f -not -name '*.swp')
export http_proxy
export https_proxy
export SSH_AUTH_SOCK
export USER
export HOME

ifeq ($(CMD), )
	command=$(DEFAULT_CMD)
else
	command=$(CMD)
endif

ifeq ($(NOCACHE), )
	nocache_opt= --no-cache
else
	nocache_opt= 
endif

ifneq ($(USE_LOCALIMG), )
	CREATER=localhost
	C_NAME=localhost
endif

ifeq ($(ROOT), )
	ifeq ($(TGT), $(SP_WORKBENCH))
		ifeq ($(shell uname), Darwin)
			useropt=-e LOCAL_UID=$(LOCAL_UID) -e LOCAL_GID=$(LOCAL_GID_MAC) -e LOCAL_HOME=$(LOCAL_HOME) -e LOCAL_WHOAMI=$(LOCAL_WHOAMI) -e LOCAL_HOSTNAME=$(LOCAL_HOSTNAME) -e LOCAL_DOCKER_GID="" 
			# Default group id is '20' on macOS. This group id is already exsit on Linux Container. So set a same value as uid.
		else
			useropt=-e LOCAL_UID=$(LOCAL_UID) -e LOCAL_GID=$(LOCAL_GID) -e LOCAL_HOME=$(LOCAL_HOME) -e LOCAL_WHOAMI=$(LOCAL_WHOAMI) -e LOCAL_HOSTNAME=$(LOCAL_HOSTNAME) -e LOCAL_DOCKER_GID=$(LOCAL_DOCKER_GID)
		endif
		useropt+= -e PATH_DOCKERFILES=$(shell pwd)
		## wr
		useropt+= --mount type=bind,src=$(HOME)/work,dst=$(HOME)/work
		useropt+= --mount type=bind,src=$(HOME)/git,dst=$(HOME)/git
		useropt+= --mount type=bind,src=$(HOME)/.shared_cache,dst=$(HOME)/.shared_cache
		ifneq ("$(wildcard $(HOME)/.ai-ignore)","")
			useropt+= --mount type=bind,src=$(HOME)/.ai-ignore,dst=$(HOME)/.ai-ignore
		endif
		ifneq ("$(wildcard $(HOME)/.codex/.*)","")
			useropt+= --mount type=bind,src=$(HOME)/.codex,dst=$(HOME)/.codex
		endif
		ifneq ("$(wildcard $(HOME)/.codex-cstm/.*)","")
			useropt+= --mount type=bind,src=$(HOME)/.codex-cstm,dst=$(HOME)/.codex-cstm
		endif
		ifneq ("$(wildcard $(HOME)/.claude/.*)","")
			useropt+= --mount type=bind,src=$(HOME)/.claude,dst=$(HOME)/.claude
		endif
		ifneq ("$(wildcard $(HOME)/.claude.json)","")
			useropt+= --mount type=bind,src=$(HOME)/.claude.json,dst=$(HOME)/.claude.json
		endif

		## ro
		useropt+= --mount type=bind,src=$(HOME)/Downloads,dst=$(HOME)/Downloads,ro
		ifneq ("$(wildcard $(HOME)/.ssh/.*)","")
			useropt+= --mount type=bind,src=$(HOME)/.ssh,dst=$(HOME)/.host.ssh,ro
			useropt+= --mount type=bind,src=$(HOME)/.ssh/known_hosts,dst=$(HOME)/.host.ssh/known_hosts
		endif
		ifneq ("$(wildcard $(HOME)/.gnupg/.*)","")
			useropt+= --mount type=bind,src=$(HOME)/.gnupg/openpgp-revocs.d,dst=$(HOME)/.gnupg/openpgp-revocs.d,ro
			useropt+= --mount type=bind,src=$(HOME)/.gnupg/private-keys-v1.d,dst=$(HOME)/.gnupg/private-keys-v1.d,ro
			useropt+= --mount type=bind,src=$(HOME)/.gnupg/pubring.kbx,dst=$(HOME)/.gnupg/pubring.kbx,ro
			useropt+= --mount type=bind,src=$(HOME)/.gnupg/pubring.kbx~,dst=$(HOME)/.gnupg/pubring.kbx~,ro
			useropt+= --mount type=bind,src=$(HOME)/.gnupg/trustdb.gpg,dst=$(HOME)/.gnupg/trustdb.gpg,ro
		endif
		ifneq ("$(wildcard $(HOME)/.gitconfig)","")
			useropt+= --mount type=bind,src=$(HOME)/.gitconfig,dst=$(HOME)/.gitconfig.add,ro
		endif
		ifneq ("$(wildcard $(HOME)/.docker.credential.gpg)","")
			useropt+= --mount type=bind,src=$(HOME)/.docker.credential.gpg,dst=$(HOME)/.docker.credential.gpg,ro
		endif
		ifneq ("$(wildcard $(HOME)/.screen_layout)","")
			useropt+= --mount type=bind,src=$(HOME)/.screen_layout,dst=$(HOME)/.screen_layout,ro
		endif

		useropt+= --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock
		command=/usr/local/bin/exec_user.sh
	else
		useropt=-u `id -u`:`id -g` -e HOME=/tmphome
	endif
endif
ifneq ($(MOUNT), )
	mt= --mount type=bind,src=$(MOUNT),dst=$(MOUNT)
endif

ifneq ($(WORK_DIR), )
	wkdir= -w $(WORK_DIR)
endif

ifeq ($(AUTORM), )
	rm= --rm
endif
ifeq ($(DAEMON), )
	dopt= -d
endif

ifeq ($(TAG), )
	tag_opt=latest
else
	tag_opt=$(TAG)
endif
ifneq ($(http_proxy), )
	use_http_proxy=--build-arg http_proxy=$(http_proxy)
endif
ifneq ($(https_proxy), )
	use_https_proxy=--build-arg https_proxy=$(https_proxy)
endif
ifneq ($(SSH_AUTH_SOCK),)
    ifneq ($(shell uname), Darwin)
        useropt+= --mount type=bind,src="$(SSH_AUTH_SOCK)",dst="$(SSH_AUTH_SOCK)" --env SSH_AUTH_SOCK="$(SSH_AUTH_SOCK)" 
    else
        useropt+= --mount type=bind,src=/run/host-services/ssh-auth.sock,dst=/run/host-services/ssh-auth.sock --env SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock 
    endif
endif
ifneq ($(CREATER), )
	builder=$(CREATER)
else
	builder=$(DEFAULT_BUILDER)
endif
ifneq ($(PORT), )
	portopt= -p 127.0.0.1:$(PORT):$(PORT)
endif
ifneq ($(C_NAME), )
	NAME=$(C_NAME)
else
	NAME=$(TGT)
endif
ifneq ($(AUTOREBUILD), )
	VERSION=latest
else
	VERSION=$(shell date '+%Y%U')
endif

define RUN_CODEX
	@bash -eu -o pipefail -c '\
if [ -n "$(USE_LOCALIMG)" ]; then \
  IMAGE="localhost/$(TGT):$(tag_opt)"; \
else \
  IMAGE="$(builder)/$(TGT):$(tag_opt)"; \
fi; \
PROJECT_ROOT="$(WORK_DIR)"; \
	WORKDIR_IN_CONTAINER="$(WORK_DIR)"; \
LOCAL_UID="$(LOCAL_UID)"; \
LOCAL_GID="$(LOCAL_GID)"; \
LOCAL_WHOAMI="$(LOCAL_WHOAMI)"; \
LOCAL_GROUP="$(LOCAL_GROUP)"; \
LOCAL_DOCKER_GID="$(LOCAL_DOCKER_GID)"; \
LOCAL_HOME="$(LOCAL_HOME)"; \
	WORK_DIR="$(WORK_DIR)"; \
CODEX_CSTM_DIR="$$LOCAL_HOME/.codex-cstm"; \
CODEXIGNORE_FILE="$$LOCAL_HOME/.ai-ignore"; \
LOCAL_CODEX_DIR="$$LOCAL_HOME/.codex"; \
TMP_DIRS=(); \
cleanup() { \
  rc="$$?"; \
  for d in "$${TMP_DIRS[@]:-}"; do \
    [ -n "$$d" ] && [ -d "$$d" ] && rm -rf -- "$$d" || true; \
  done; \
  exit "$$rc"; \
}; \
trap cleanup EXIT; \
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found" >&2; exit 1; }; \
DOCKER_MOUNTS=(); \
DOCKER_MOUNTS+=("-v" "$$PROJECT_ROOT:$$PROJECT_ROOT:rw"); \
case "$$WORKDIR_IN_CONTAINER" in \
  "$$PROJECT_ROOT"/*) ;; \
  "$$PROJECT_ROOT") ;; \
  *) DOCKER_MOUNTS+=("-v" "$$WORKDIR_IN_CONTAINER:$$WORKDIR_IN_CONTAINER:rw");; \
esac; \
CONTAINER_HOME="/home/$$LOCAL_WHOAMI"; \
mkdir -p -- "$$LOCAL_CODEX_DIR"; \
DOCKER_MOUNTS+=("-v" "$$LOCAL_CODEX_DIR:$$CONTAINER_HOME/.codex:rw"); \
if [ -d "$$CODEX_CSTM_DIR" ]; then \
  DOCKER_MOUNTS+=("-v" "$$CODEX_CSTM_DIR:$$CONTAINER_HOME/.codex-cstm:ro"); \
fi; \
if [ -d "$$LOCAL_HOME/.ssh" ]; then \
  DOCKER_MOUNTS+=("-v" "$$LOCAL_HOME/.ssh:$$CONTAINER_HOME/.ssh:ro"); \
fi; \
if [ -f "$$LOCAL_HOME/.gitconfig" ]; then \
  DOCKER_MOUNTS+=("-v" "$$LOCAL_HOME/.gitconfig:$$CONTAINER_HOME/.gitconfig:ro"); \
fi; \
if [ -f "$$CODEXIGNORE_FILE" ]; then \
  echo "[prep] Applying ignore rules from: $$CODEXIGNORE_FILE"; \
  shopt -s nullglob globstar dotglob; \
  while IFS= read -r raw || [ -n "$$raw" ]; do \
    line="$${raw#"$${raw%%[![:space:]]*}"}"; \
    line="$${line%"$${line##*[![:space:]]}"}"; \
    [ -z "$$line" ] && continue; \
    case "$$line" in \#*) continue ;; esac; \
    matches=(); \
    if [ "$${line#/}" != "$$line" ]; then \
      while IFS= read -r m; do matches+=("$$m"); done < <(compgen -G "$$line" || true); \
      [ "$${#matches[@]}" -eq 0 ] && matches=("$$line"); \
    else \
      while IFS= read -r m; do matches+=("$$m"); done < <(cd "$$PROJECT_ROOT" && compgen -G "$$line" || true); \
      [ "$${#matches[@]}" -eq 0 ] && matches=("$$line"); \
    fi; \
    for p in "$${matches[@]}"; do \
      p="$${p#./}"; \
      if [ "$${p#/}" != "$$p" ]; then \
        host_path="$$p"; \
        container_path="$$p"; \
      else \
        host_path="$$PROJECT_ROOT/$$p"; \
        container_path="$$WORKDIR_IN_CONTAINER/$$p"; \
      fi; \
      if [ -d "$$host_path" ]; then \
        empty_dir="$$(mktemp -d -t codex-emptydir-XXXXXX)"; \
        TMP_DIRS+=("$$empty_dir"); \
        DOCKER_MOUNTS+=("-v" "$$empty_dir:$$container_path:ro"); \
        echo "  [hide dir]  $$host_path -> $$container_path"; \
      elif [ -e "$$host_path" ]; then \
        DOCKER_MOUNTS+=("-v" "/dev/null:$$container_path:ro"); \
        echo "  [hide file] $$host_path -> $$container_path"; \
      else \
        echo "  [skip] not found: $$host_path"; \
      fi; \
    done; \
  done < "$$CODEXIGNORE_FILE"; \
  shopt -u nullglob globstar dotglob; \
else \
  echo "[info] $$CODEXIGNORE_FILE not found; no ignore mounts applied."; \
fi; \
DOCKER_ENVS=( \
  "-e" "LOCAL_WHOAMI=$$LOCAL_WHOAMI" \
  "-e" "LOCAL_GROUP=$$LOCAL_GROUP" \
  "-e" "LOCAL_UID=$$LOCAL_UID" \
  "-e" "LOCAL_GID=$$LOCAL_GID" \
  "-e" "LOCAL_DOCKER_GID=$$LOCAL_DOCKER_GID" \
  "-e" "WORK_DIR=$$WORK_DIR" \
); \
if [ -n "$${SSH_AUTH_SOCK:-}" ]; then \
  if [ "$$(uname -s)" = "Darwin" ]; then \
    if [ -S /run/host-services/ssh-auth.sock ]; then \
      DOCKER_MOUNTS+=("-v" "/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock"); \
      DOCKER_ENVS+=("-e" "SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock"); \
    fi; \
  elif [ -S "$$SSH_AUTH_SOCK" ]; then \
    DOCKER_MOUNTS+=("-v" "$$SSH_AUTH_SOCK:$$SSH_AUTH_SOCK"); \
    DOCKER_ENVS+=("-e" "SSH_AUTH_SOCK=$$SSH_AUTH_SOCK"); \
  fi; \
fi; \
echo "[run] docker run --rm $$IMAGE"; \
echo "      project: $$PROJECT_ROOT"; \
echo "      workdir : $$WORKDIR_IN_CONTAINER (same as host)"; \
echo "      env     : LOCAL_WHOAMI=$$LOCAL_WHOAMI LOCAL_GROUP=$$LOCAL_GROUP LOCAL_UID=$$LOCAL_UID LOCAL_GID=$$LOCAL_GID"; \
if [ -f "$$WORKDIR_IN_CONTAINER/.codex-build" ]; then \
  echo "[pre] Running ./.codex-build inside same container..."; \
  mapfile -t IMAGE_ENTRYPOINT < <(docker image inspect --format '\''{{range .Config.Entrypoint}}{{println .}}{{end}}'\'' "$$IMAGE"); \
  if [ "$${#IMAGE_ENTRYPOINT[@]}" -eq 0 ]; then \
    exec docker run --rm -it \
      --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
      "$${DOCKER_ENVS[@]}" \
      -w "$$WORKDIR_IN_CONTAINER" \
      "$${DOCKER_MOUNTS[@]}" \
      --entrypoint /bin/bash \
      "$$IMAGE" \
      -lc '\''set -euo pipefail; bash "./.codex-build"; exec codex "$$@"'\'' -- "$$@"; \
  fi; \
  exec docker run --rm -it \
    --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
    "$${DOCKER_ENVS[@]}" \
    -w "$$WORKDIR_IN_CONTAINER" \
    "$${DOCKER_MOUNTS[@]}" \
    --entrypoint /bin/bash \
    "$$IMAGE" \
    -lc '\''set -euo pipefail; bash "./.codex-build"; exec "$$@"'\'' -- "$${IMAGE_ENTRYPOINT[@]}" codex "$$@"; \
else \
  exec docker run --rm -it \
    --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
    "$${DOCKER_ENVS[@]}" \
    -w "$$WORKDIR_IN_CONTAINER" \
    "$${DOCKER_MOUNTS[@]}" \
    "$$IMAGE" \
    codex "$$@"; \
fi' -- $(ARGS)
endef

define RUN_CLAUDE
	@bash -eu -o pipefail -c '\
if [ -n "$(USE_LOCALIMG)" ]; then \
  IMAGE="localhost/$(TGT):$(tag_opt)"; \
else \
  IMAGE="$(builder)/$(TGT):$(tag_opt)"; \
fi; \
PROJECT_ROOT="$(WORK_DIR)"; \
	WORKDIR_IN_CONTAINER="$(WORK_DIR)"; \
LOCAL_UID="$(LOCAL_UID)"; \
LOCAL_GID="$(LOCAL_GID)"; \
LOCAL_WHOAMI="$(LOCAL_WHOAMI)"; \
LOCAL_GROUP="$(LOCAL_GROUP)"; \
LOCAL_DOCKER_GID="$(LOCAL_DOCKER_GID)"; \
LOCAL_HOME="$(LOCAL_HOME)"; \
	WORK_DIR="$(WORK_DIR)"; \
CLAUDE_CSTM_DIR="$$LOCAL_HOME/.claude-cstm"; \
CLAUDEIGNORE_FILE="$$LOCAL_HOME/.ai-ignore"; \
LOCAL_CLAUDE_DIR="$$LOCAL_HOME/.claude"; \
LOCAL_CLAUDE_JSON="$$LOCAL_HOME/.claude.json"; \
TMP_DIRS=(); \
cleanup() { \
  rc="$$?"; \
  for d in "$${TMP_DIRS[@]:-}"; do \
    [ -n "$$d" ] && [ -d "$$d" ] && rm -rf -- "$$d" || true; \
  done; \
  exit "$$rc"; \
}; \
trap cleanup EXIT; \
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found" >&2; exit 1; }; \
DOCKER_MOUNTS=(); \
DOCKER_MOUNTS+=("-v" "$$PROJECT_ROOT:$$PROJECT_ROOT:rw"); \
case "$$WORKDIR_IN_CONTAINER" in \
  "$$PROJECT_ROOT"/*) ;; \
  "$$PROJECT_ROOT") ;; \
  *) DOCKER_MOUNTS+=("-v" "$$WORKDIR_IN_CONTAINER:$$WORKDIR_IN_CONTAINER:rw");; \
esac; \
CONTAINER_HOME="/home/$$LOCAL_WHOAMI"; \
mkdir -p -- "$$LOCAL_CLAUDE_DIR"; \
DOCKER_MOUNTS+=("-v" "$$LOCAL_CLAUDE_DIR:$$CONTAINER_HOME/.claude:rw"); \
DOCKER_MOUNTS+=("-v" "$$LOCAL_CLAUDE_JSON:$$CONTAINER_HOME/.claude.json:rw"); \
if [ -d "$$CLAUDE_CSTM_DIR" ]; then \
  DOCKER_MOUNTS+=("-v" "$$CLAUDE_CSTM_DIR:$$CONTAINER_HOME/.claude-cstm:ro"); \
fi; \
if [ -d "$$LOCAL_HOME/.ssh" ]; then \
  DOCKER_MOUNTS+=("-v" "$$LOCAL_HOME/.ssh:$$CONTAINER_HOME/.ssh:ro"); \
fi; \
if [ -f "$$LOCAL_HOME/.gitconfig" ]; then \
  DOCKER_MOUNTS+=("-v" "$$LOCAL_HOME/.gitconfig:$$CONTAINER_HOME/.gitconfig:ro"); \
fi; \
if [ -f "$$CLAUDEIGNORE_FILE" ]; then \
  echo "[prep] Applying ignore rules from: $$CLAUDEIGNORE_FILE"; \
  shopt -s nullglob globstar dotglob; \
  while IFS= read -r raw || [ -n "$$raw" ]; do \
    line="$${raw#"$${raw%%[![:space:]]*}"}"; \
    line="$${line%"$${line##*[![:space:]]}"}"; \
    [ -z "$$line" ] && continue; \
    case "$$line" in \#*) continue ;; esac; \
    matches=(); \
    if [ "$${line#/}" != "$$line" ]; then \
      while IFS= read -r m; do matches+=("$$m"); done < <(compgen -G "$$line" || true); \
      [ "$${#matches[@]}" -eq 0 ] && matches=("$$line"); \
    else \
      while IFS= read -r m; do matches+=("$$m"); done < <(cd "$$PROJECT_ROOT" && compgen -G "$$line" || true); \
      [ "$${#matches[@]}" -eq 0 ] && matches=("$$line"); \
    fi; \
    for p in "$${matches[@]}"; do \
      p="$${p#./}"; \
      if [ "$${p#/}" != "$$p" ]; then \
        host_path="$$p"; \
        container_path="$$p"; \
      else \
        host_path="$$PROJECT_ROOT/$$p"; \
        container_path="$$WORKDIR_IN_CONTAINER/$$p"; \
      fi; \
      if [ -d "$$host_path" ]; then \
        empty_dir="$$(mktemp -d -t claude-emptydir-XXXXXX)"; \
        TMP_DIRS+=("$$empty_dir"); \
        DOCKER_MOUNTS+=("-v" "$$empty_dir:$$container_path:ro"); \
        echo "  [hide dir]  $$host_path -> $$container_path"; \
      elif [ -e "$$host_path" ]; then \
        DOCKER_MOUNTS+=("-v" "/dev/null:$$container_path:ro"); \
        echo "  [hide file] $$host_path -> $$container_path"; \
      else \
        echo "  [skip] not found: $$host_path"; \
      fi; \
    done; \
  done < "$$CLAUDEIGNORE_FILE"; \
  shopt -u nullglob globstar dotglob; \
else \
  echo "[info] $$CLAUDEIGNORE_FILE not found; no ignore mounts applied."; \
fi; \
DOCKER_ENVS=( \
  "-e" "LOCAL_WHOAMI=$$LOCAL_WHOAMI" \
  "-e" "LOCAL_GROUP=$$LOCAL_GROUP" \
  "-e" "LOCAL_UID=$$LOCAL_UID" \
  "-e" "LOCAL_GID=$$LOCAL_GID" \
  "-e" "LOCAL_DOCKER_GID=$$LOCAL_DOCKER_GID" \
  "-e" "WORK_DIR=$$WORK_DIR" \
); \
if [ -n "$${SSH_AUTH_SOCK:-}" ]; then \
  if [ "$$(uname -s)" = "Darwin" ]; then \
    if [ -S /run/host-services/ssh-auth.sock ]; then \
      DOCKER_MOUNTS+=("-v" "/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock"); \
      DOCKER_ENVS+=("-e" "SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock"); \
    fi; \
  elif [ -S "$$SSH_AUTH_SOCK" ]; then \
    DOCKER_MOUNTS+=("-v" "$$SSH_AUTH_SOCK:$$SSH_AUTH_SOCK"); \
    DOCKER_ENVS+=("-e" "SSH_AUTH_SOCK=$$SSH_AUTH_SOCK"); \
  fi; \
fi; \
echo "[run] docker run --rm $$IMAGE"; \
echo "      project: $$PROJECT_ROOT"; \
echo "      workdir : $$WORKDIR_IN_CONTAINER (same as host)"; \
echo "      env     : LOCAL_WHOAMI=$$LOCAL_WHOAMI LOCAL_GROUP=$$LOCAL_GROUP LOCAL_UID=$$LOCAL_UID LOCAL_GID=$$LOCAL_GID"; \
if [ -f "$$WORKDIR_IN_CONTAINER/.claude-build" ]; then \
  echo "[pre] Running ./.claude-build inside same container..."; \
  mapfile -t IMAGE_ENTRYPOINT < <(docker image inspect --format '\''{{range .Config.Entrypoint}}{{println .}}{{end}}'\'' "$$IMAGE"); \
  if [ "$${#IMAGE_ENTRYPOINT[@]}" -eq 0 ]; then \
    exec docker run --rm -it \
      --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
      "$${DOCKER_ENVS[@]}" \
      -w "$$WORKDIR_IN_CONTAINER" \
      "$${DOCKER_MOUNTS[@]}" \
      --entrypoint /bin/bash \
      "$$IMAGE" \
      -lc '\''set -euo pipefail; bash "./.claude-build"; exec claude "$$@"'\'' -- "$$@"; \
  fi; \
  exec docker run --rm -it \
    --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
    "$${DOCKER_ENVS[@]}" \
    -w "$$WORKDIR_IN_CONTAINER" \
    "$${DOCKER_MOUNTS[@]}" \
    --entrypoint /bin/bash \
    "$$IMAGE" \
    -lc '\''set -euo pipefail; bash "./.claude-build"; exec "$$@"'\'' -- "$${IMAGE_ENTRYPOINT[@]}" claude "$$@"; \
else \
  exec docker run --rm -it \
    --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
    "$${DOCKER_ENVS[@]}" \
    -w "$$WORKDIR_IN_CONTAINER" \
    "$${DOCKER_MOUNTS[@]}" \
    "$$IMAGE" \
    claude "$$@"; \
fi' -- $(ARGS)
endef

.PHONY: all
all: check_health start ## [Default] Exec function of  'build' -> 'start' -> 'attach'
ifneq ($(dopt), )
	make -C . attach
endif

.PHONY: repopull
repopull: ## Pull the remote repositroy.
	git pull

.PHONY: build
build: check_health check_target $(PATH_MTX)$(TGT).$(builder).$(VERSION) ## Build a target docker image. If the target container already exists, skip this section.

.PHONY: pull
pull: check_health check_target
ifeq ($(USE_LOCALIMG), )
	docker pull $(builder)/$(TGT):$(tag_opt) || :
endif

.PHONY: start
start: check_health check_target pull ## Start a target docker image. If the target container already exists, skip this section.
ifeq ($(TGT), $(SP_CODEX))
	$(RUN_CODEX)
else
ifeq ($(TGT), $(SP_CLAUDE))
	$(RUN_CLAUDE)
else
	test -n "$(CONTAINER_ID)" || $(D) run --name $(NAME) -it $(useropt) $(rm) $(mt) $(wkdir) $(portopt) $(dopt) $(builder)/$(TGT):$(tag_opt) $(command)
endif
endif
ifneq ($(dopt), )
	test -n "$(CONTAINER_ID)" || sleep 1 ## Magic sleep. Wait for container to stabilize.
endif

.PHONY: install
install: $(HOME)/work $(HOME)/git $(HOME)/.shared_cache $(HOME)/Downloads

$(HOME)/work $(HOME)/git $(HOME)/.shared_cache $(HOME)/Downloads:
	mkdir -p ${@}

.PHONY: uninstall
uninstall:
	rmdir $(HOME)/work $(HOME)/git $(HOME)/.shared_cache $(HOME)/Downloads

.PHONY: attach
attach: check_health check_target ## Attach the target docker container.
	test -z "$(CONTAINER_ID)" || $(D) exec -it $(NAME) $(command)

.PHONY: stop
stop: check_health check_target ## Force stop the target docker container.
	test -z "$(CONTAINER_ID)" || $(D) rm -f $(CONTAINER_ID)

.PHONY: clean
clean: check_health check_target ## Remove the target dokcer image.
	$(D) rmi -f $(shell docker images --filter "reference=$(builder)/$(TGT)" -q) && \
	rm $(PATH_MTX)$(TGT).$(builder)*

.PHONY: allclean
allclean: are_you_sure ## [[Powerful Option]] Cleanup **ALL** docker object
	make -C . allrm allrmi allrmo

.PHONY: allrm
allrm: check_health ## [[Powerful Option]] Cleanup **ALL** docker container.
	$(D) container prune || :
	$(D) ps -aq | xargs $(D) rm || :

.PHONY: allrmi
allrmi: check_health ## [[Powerful Option]] Cleanup **ALL** docker images.
	$(D) image prune || :
	$(D) images -aq | xargs $(D) rmi -f || :

.PHONY: allrmo
allrmo: ## [[Powerful Option]] Cleanup **ALL** docker object
	$(D) system prune --volumes

.PHONY: check_health
check_health:
	@$(D) version > /dev/null || (echo "[Makefile Killing]: cannot running this script. Cannot connect to docker daemon."; exit 1)
	$(eval CONTAINER_ID?=$$(shell docker ps -aq -f name="$(NAME)"))

.PHONY: check_target
check_target:
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif

L_TYPE=$(shell cat dockerfiles/$(TGT)/Dockerfile | grep FROM | head -n1 | sed -n 's/^FROM \([^:]*\):.*$$/\1/p')
L_TAG=$(shell cat dockerfiles/$(TGT)/Dockerfile | grep FROM | head -n1 | sed -n 's/^.*\$${\([^}]*\)}.*$$/\1/p')
$(PATH_MTX)$(TGT).$(builder).$(VERSION): $(TGT_SRCS)
	$(D) image build $(nocache_opt) $(use_http_proxy) $(use_https_proxy) --build-arg $(L_TAG)=$(shell cat version/$(L_TYPE)/$(L_TAG)) -t $(builder)/$(TGT):$(VERSION) dockerfiles/$(TGT)/. && \
		$(D) tag $(builder)/$(TGT):$(VERSION) $(builder)/$(TGT):latest && \
		touch $(PATH_MTX)$(TGT).$(builder).$(VERSION)

.PHONY: are_you_sure
are_you_sure:
	@echo -n "Are you sure? [y/N]: "
	@read -r answer && test "$$answer" = "y"

.PHONY: help
	all: help
help: ## Display the options.
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
	}' $(MAKEFILE_LIST)
