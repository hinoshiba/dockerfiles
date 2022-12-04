# mydocker makefile@hinoshiba:##
#  usage: ## make [target=<targetpath>] [root=y] [daemon=n] [autorm=n] [mount=<path>] [creater=<name>] [port=<number>] [cname=<container name>] [cmd=<exec command>] [autorebuild=n]
#  sample: ## make target=golang root=y autorm=n daemon=n mount=/home/hinoshiba/Downloads creater=hinoshiba port=80 cname=run02
#  sample: ## make target=tor gui=firefox
#  =======options========  :##
## You can add text at help menu, pattern of '#<string>: <string2>'

## const
DEFAULT_CMD=/bin/bash
D=docker
SP_WORKBENCH=workbench
SP_TOR=tor
PATH_MTX=.mtx/

## args
TGT=${target}
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

## import
TGT_SRCS=$(shell find ./dockerfiles/$(TGT) -type f -not -name '*.swp')
export http_proxy
export https_proxy
export USER
export HOME

ifeq ($(CMD), )
	command=$(DEFAULT_CMD)
else
	command=$(CMD)
endif

buildopt=
ifeq ($(ROOT), )
	ifeq ($(TGT), $(SP_WORKBENCH))
		ifeq ($(shell uname), Darwin)
			useropt=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -u ${USER}) -e LOCAL_HOME=$(HOME) -e LOCAL_WHOAMI=$(shell whoami) -e LOCAL_HOSTNAME=$(shell hostname)
			# Default group id is '20' on macOS. This group id is already exsit on Linux Container. So set a same value as uid.
		else
			useropt=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -g ${USER}) -e LOCAL_HOME=$(HOME) -e LOCAL_WHOAMI=$(shell whoami) -e LOCAL_HOSTNAME=$(shell hostname)
			buildopt+=--build-arg local_docker_gid=$(shell getent group docker | awk  -F: '{print $$3}')
		endif
		## wr
		useropt+= --mount type=bind,src=$(HOME)/work,dst=$(HOME)/work
		useropt+= --mount type=bind,src=$(HOME)/git,dst=$(HOME)/git
		useropt+= --mount type=bind,src=$(HOME)/.shared_cache,dst=$(HOME)/.shared_cache

		## ro
		useropt+= --mount type=bind,src=$(HOME)/.ssh,dst=$(HOME)/.host.ssh,ro
		useropt+= --mount type=bind,src=$(HOME)/.ssh/known_hosts,dst=$(HOME)/.host.ssh/known_hosts
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/openpgp-revocs.d,dst=$(HOME)/.gnupg/openpgp-revocs.d,ro
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/private-keys-v1.d,dst=$(HOME)/.gnupg/private-keys-v1.d,ro
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/pubring.kbx,dst=$(HOME)/.gnupg/pubring.kbx,ro
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/pubring.kbx~,dst=$(HOME)/.gnupg/pubring.kbx~,ro
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/trustdb.gpg,dst=$(HOME)/.gnupg/trustdb.gpg,ro
		useropt+= --mount type=bind,src=$(HOME)/.gitconfig,dst=$(HOME)/.gitconfig,ro
		useropt+= --mount type=bind,src=$(HOME)/.muttrc.add,dst=$(HOME)/.muttrc.add,ro
		useropt+= --mount type=bind,src=$(HOME)/.muttrc.signature,dst=$(HOME)/.muttrc.signature,ro
		useropt+= --mount type=bind,src=$(HOME)/.muttrc.passwords.gpg,dst=$(HOME)/.muttrc.passwords.gpg,ro
		useropt+= --mount type=bind,src=$(HOME)/Downloads,dst=$(HOME)/Downloads,ro
		useropt+= --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock
		command=/usr/local/bin/exec_user.sh
	else
		useropt=-u `id -u`:`id -g`
	endif
endif
ifneq ($(MOUNT), )
	mt= --mount type=bind,src=$(MOUNT),dst=$(MOUNT)
endif

ifeq ($(AUTORM), )
	rm= --rm
endif
ifeq ($(DAEMON), )
	dopt= -d
endif

ifneq ($(http_proxy), )
	use_http_proxy=--build-arg http_proxy=$(http_proxy)
endif
ifneq ($(https_proxy), )
	use_https_proxy=--build-arg https_proxy=$(https_proxy)
endif
ifneq ($(CREATER), )
	builder=$(CREATER)
else
	builder=$(USER)
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

.PHONY: all
all: check_health repopull start ## [Default] Exec function of 'repopull' -> 'start' -> 'attach'
ifneq ($(dopt), )
	make -C . attach
endif

.PHONY: repopull
repopull: check_health ## Pull the remote repositroy.
	test -n "$(CONTAINER_ID)" || git pull

.PHONY: build
build: check_health check_target $(PATH_MTX)$(TGT).$(builder).$(VERSION) ## Build a target docker image. If the target container already exists, skip this section.

.PHONY: start
start: check_health check_target build ## Start a target docker image. If the target container already exists, skip this section. And auto exec 'make build' when have not image.
ifeq ($(TGT), $(SP_TOR))
	test -n "$(CONTAINER_ID)" || echo "[INFO] you need exec 'sudo xhost - && sudo xhost + local' before this command."
	test -n "$(CONTAINER_ID)" || docker run -it -v ~/.Xauthority:/root/.Xauthority --rm -e DISPLAY=host.docker.internal:0 "$(builder)/tor" /work/run.sh $(GUI)
else
	test -n "$(CONTAINER_ID)" || $(D) run --name $(NAME) -it $(useropt) $(rm) $(mt) $(portopt) $(dopt) $(builder)/$(TGT) $(command)
ifneq ($(dopt), )
	test -n "$(CONTAINER_ID)" || sleep 1 ## Magic sleep. Wait for container to stabilize.
endif
endif

.PHONY: attach
attach: check_health check_target ## Attach the target docker container.
	test -z "$(CONTAINER_ID)" || $(D) exec -it $(NAME) $(command)

.PHONY: stop
stop: check_health check_target ## Force stop the target docker container.
	test -z "$(CONTAINER_ID)" || $(D) rm -f $(CONTAINER_ID)

.PHONY: clean
clean: check_health check_target ## Remove the target dokcer image.
	$(D) rmi $(builder)/$(TGT) || :
	rm $(PATH_MTX)$(TGT).$(builder)* || :

.PHONY: allrm
allrm: check_health ## [[Powerful Option]] Cleanup **ALL** docker container.
	$(D) container prune
	$(D) ps -aq | xargs $(D) rm

.PHONY: allrmi
allrmi: check_health ## [[Powerful Option]] Cleanup **ALL** docker images.
	$(D) image prune
	$(D) images -aq | xargs $(D) rmi

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

$(PATH_MTX)$(TGT).$(builder).$(VERSION): $(TGT_SRCS)
	@$(D) image build $(use_http_proxy) $(use_https_proxy) $(buildopt) -t $(builder)/$(TGT):$(VERSION) dockerfiles/$(TGT)/. && touch $(PATH_MTX)$(TGT).$(builder).$(VERSION)

.PHONY: help
	all: help
help: ## Display the options.
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
	}' $(MAKEFILE_LIST)
