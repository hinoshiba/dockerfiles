# USAGE: make [target=<targetpath>] [root=y] [autorm=n] [mount=<path>] [creater=<name>] [port=<number>] [cname=<container name>]
# example: make target=golang root=y autorm=y mount=/home/hinoshiba/Downloads creater=hinoshiba port=80 cname=run02
D=docker

TGT=${target}
ARGS=${args}
MOUNT=${mount}
ROOT=${root}
AUTORM=${autorm}
CREATER=${creater}
PORT=${port}
C_NAME=${cname}

SP_WORKBENCH=workbench

SRCS := $(shell find . -type f)
export http_proxy
export https_proxy
export USER
export HOME

ifeq ($(ROOT), )
	ifeq ($(TGT), $(SP_WORKBENCH))
		ifeq ($(shell uname), Darwin)
			useropt=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -u ${USER}) -e LOCAL_HOME=$(HOME) -e LOCAL_WHOAMI=$(shell whoami)
			# Default group id is '20' on macOS. This group id is already exsit on Linux Container. So set a same value as uid.
		else
			useropt=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -g ${USER}) -e LOCAL_HOME=$(HOME) -e LOCAL_WHOAMI=$(shell whoami)
		endif
		useropt+= --mount type=bind,src=$(HOME),dst=/mnt/$(HOME),readonly
		useropt+= --mount type=bind,src=$(HOME)/work,dst=/mnt/$(HOME)/work
		useropt+= --mount type=bind,src=$(HOME)/git,dst=/mnt/$(HOME)/git
		useropt+= --mount type=bind,src=$(HOME)/shared_cache,dst=/mnt/$(HOME)/shared_cache
		useropt+= --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock
	else
		useropt=-u `id -u`:`id -g`
	endif
endif
ifneq ($(MOUNT), )
	mt=--mount type=bind,src=$(MOUNT),dst=$(MOUNT)
endif

ifeq ($(AUTORM), )
	rm=--rm
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
	portopt=-p 127.0.0.1:$(PORT):$(PORT)
endif
ifneq ($(C_NAME), )
	nameopt=$(C_NAME)
else
	nameopt=$(TGT)
endif


.PHONY: all
all: build run ## exec "build" and "run"
.PHONY: build
build: $(SRCS) ## build to all container
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
	$(D) image build $(use_http_proxy) $(use_https_proxy) -t $(builder)/$(TGT) dockerfiles/$(TGT)/.

.PHONY: run
run: $(SRCS) ## start up to all container
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
	$(D) run --name $(nameopt) -it $(useropt) $(rm) $(mt) $(portopt) $(builder)/$(TGT) /bin/bash

.PHONY: attach
attach: ## attach container
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
	$(D) exec -it $(TGT) /bin/bash

.PHONY: clean
clean: ## stop container and cleanup data
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
	$(D) rmi $(builder)/$(TGT)

.PHONY: allrm
allrm: ## cleanup all container
	$(D) ps -aq | xargs $(D) rm

.PHONY: allrmi
allrmi: ## cleanup all images
	$(D) images -aq | xargs $(D) rmi

.PHONY: help
	all: help
help: ## help
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
	}' $(MAKEFILE_LIST)
