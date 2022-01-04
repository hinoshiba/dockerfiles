# USAGE: make [target=<targetpath>] [noroot=y] [autorm=n] [mount=<path>] [creater=<name>] [port=<number>]
# example: make target=golang noroot=y autorm=y mount=/home/hinoshiba/Downloads creater=hinoshiba port=80
D=docker

TGT=${target}
ARGS=${args}
MOUNT=${mount}
NOROOT=${noroot}
AUTORM=${autorm}
CREATER=${creater}
PORT=${port}

SRCS := $(shell find . -type f)
export http_proxy
export https_proxy
export USER


ifneq ($(NOROOT), )
	root=-u `id -u`:`id -g`
endif
ifeq ($(TGT), workbench)
	root=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -g ${USER})
endif

ifeq ($(AUTORM), )
	rm=--rm
endif
ifneq ($(MOUNT), )
	mt=--mount type=bind,src=$(MOUNT),dst=$(MOUNT)
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
	$(D) run --name $(TGT) -it $(root) $(rm) $(mt) $(portopt) $(builder)/$(TGT) /bin/bash

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
