# mydocker makefile@hinoshiba:##
#  usage: ## make [target=<targetpath>] [root=y] [daemon=n] [autorm=n] [mount=<path>] [creater=<name>] [port=<number>] [cname=<container name>]
#  sample: ## make target=golang root=y autorm=n daemon=n mount=/home/hinoshiba/Downloads creater=hinoshiba port=80 cname=run02
#  =======options========  :##
## You can add text at help menu, pattern of '#<string>: <string2>'

## const
INIT_SHELL=/bin/bash
D=docker
SP_WORKBENCH=workbench

## args
TGT=${target}
MOUNT=${mount}
ROOT=${root}
AUTORM=${autorm}
CREATER=${creater}
PORT=${port}
C_NAME=${cname}
DAEMON=${daemon}

## import
SRCS := $(shell find . -type f)
export http_proxy
export https_proxy
export USER
export HOME

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
		useropt+= --mount type=bind,src=$(HOME)/.ssh,dst=$(HOME)/.ssh,ro
		useropt+= --mount type=bind,src=$(HOME)/.ssh/known_hosts,dst=$(HOME)/.ssh/known_hosts
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/openpgp-revocs.d,dst=$(HOME)/.gnupg/openpgp-revocs.d,ro
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/private-keys-v1.d,dst=$(HOME)/.gnupg/private-keys-v1.d,ro
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/pubring.kbx,dst=$(HOME)/.gnupg/pubring.kbx,ro
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/pubring.kbx~,dst=$(HOME)/.gnupg/pubring.kbx~,ro
		useropt+= --mount type=bind,src=$(HOME)/.gnupg/trustdb.gpg,dst=$(HOME)/.gnupg/trustdb.gpg,ro
		useropt+= --mount type=bind,src=$(HOME)/.gitconfig,dst=$(HOME)/.gitconfig,ro
		useropt+= --mount type=bind,src=$(HOME)/.muttrc.add,dst=$(HOME)/.muttrc.add,ro
		useropt+= --mount type=bind,src=$(HOME)/.muttrc.signature,dst=$(HOME)/.muttrc.signature,ro
		useropt+= --mount type=bind,src=$(HOME)/Downloads,dst=$(HOME)/Downloads,ro
		useropt+= --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock
		INIT_SHELL=/usr/local/bin/exec_user.sh
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

.PHONY: all
all: repopull start attach ## [Default] Exec function of 'repopull' -> 'start' -> 'attach'

.PHONY: repopull
repopull: ## Pull the remote repositroy.
ifeq ($(shell docker ps -aq -f name="$(NAME)"), )
	git pull
endif
.PHONY: build
build: $(SRCS) ## Build a target docker image. If the target container already exists, skip this section.
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
ifeq ($(shell docker ps -aq -f name="$(NAME)"), )
	$(D) image build $(use_http_proxy) $(use_https_proxy) $(buildopt) -t $(builder)/$(TGT) dockerfiles/$(TGT)/.
endif

.PHONY: start
start: $(SRCS) ## Start a target docker image. If the target container already exists, skip this section. And auto exec 'make build' when have not image.
ifeq ($(shell docker images -aq "$(builder)/$(TGT)"), )
	make build
endif
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
ifeq ($(shell docker ps -aq -f name="$(NAME)"), )
	$(D) run --name $(NAME) -it $(useropt) $(rm) $(mt) $(portopt) $(dopt) $(builder)/$(TGT) $(INIT_SHELL)
	sleep 1 ## Magic sleep. Wait for container to stabilize.
endif

.PHONY: attach
attach: ## Attach the target docker container.
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
ifneq ($(dopt), )
	$(D) exec -it $(NAME) $(INIT_SHELL)
endif

.PHONY: stop
stop: ## Force stop the target docker container.
ifeq ($(NAME), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
ifneq ($(shell docker ps -aq -f name="$(NAME)"), )
	$(D) rm -f $(shell docker ps -aq -f name="$(NAME)")
endif

.PHONY: clean
clean: ## Remove the target dokcer image.
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
	$(D) rmi $(builder)/$(TGT)

.PHONY: allrm
allrm: ## [[Powerful Option]] Cleanup **ALL** docker container.
	$(D) ps -aq | xargs $(D) rm

.PHONY: allrmi
allrmi: ## [[Powerful Option]] Cleanup **ALL** docker images.
	$(D) images -aq | xargs $(D) rmi

.PHONY: help
	all: help
help: ## Display the options.
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
	}' $(MAKEFILE_LIST)
