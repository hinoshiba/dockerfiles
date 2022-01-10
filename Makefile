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

ifeq ($(ROOT), )
	ifeq ($(TGT), $(SP_WORKBENCH))
		ifeq ($(shell uname), Darwin)
			useropt=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -u ${USER}) -e LOCAL_HOME=$(HOME) -e LOCAL_WHOAMI=$(shell whoami) -e LOCAL_HOSTNAME=$(shell hostname)
			# Default group id is '20' on macOS. This group id is already exsit on Linux Container. So set a same value as uid.
		else
			useropt=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -g ${USER}) -e LOCAL_HOME=$(HOME) -e LOCAL_WHOAMI=$(shell whoami) -e LOCAL_HOSTNAME=$(shell hostname)
		endif
		useropt+= --mount type=bind,src=$(HOME),dst=/mnt/$(HOME),readonly
		useropt+= --mount type=bind,src=$(HOME)/work,dst=/mnt/$(HOME)/work
		useropt+= --mount type=bind,src=$(HOME)/git,dst=/mnt/$(HOME)/git
		useropt+= --mount type=bind,src=$(HOME)/shared_cache,dst=/mnt/$(HOME)/shared_cache
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
all: build start attach ## [Default] Exec function of 'build' -> 'start' -> 'attach'

.PHONY: build
build: $(SRCS) ## Build a target docker image. If the target container already exists, skip this section.
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
ifeq ($(shell docker ps -aq -f name="$(NAME)"), )
	$(D) image build $(use_http_proxy) $(use_https_proxy) -t $(builder)/$(TGT) dockerfiles/$(TGT)/.
endif


.PHONY: start
start: $(SRCS) ## Start a target docker image. If the target container already exists, skip this section.
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
ifeq ($(shell docker ps -aq -f name="$(NAME)"), )
	$(D) run --name $(NAME) -it $(useropt) $(rm) $(mt) $(portopt) $(dopt) $(builder)/$(TGT) $(INIT_SHELL)
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
