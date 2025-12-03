# mydocker makefile@hinoshiba:##
#  usage: ## make [target=<targetpath>] [tag=<tag>] [root=y] [daemon=n] [autorm=n] [mount=<path>] [creater=<name>] [port=<number>] [cname=<container name>] [cmd=<exec command>] [autorebuild=n] [nocache=n] [workdir=<work dir>] [localimg=y]
#  sample: ## make target=golang root=y autorm=n daemon=n mount=/home/hinoshiba/Downloads creater=hinoshiba port=80 cname=run02
#  sample: ## make target=tor gui=firefox
#  =======options========  :##
## You can add text at help menu, pattern of '#<string>: <string2>'

## const
DEFAULT_CMD=/bin/bash
D=docker
SP_WORKBENCH=workbench
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
WK_DIR=${workdir}
USE_LOCALIMG=${localimg}

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
			useropt=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -u ${USER}) -e LOCAL_HOME=$(HOME) -e LOCAL_WHOAMI=$(shell whoami) -e LOCAL_HOSTNAME=$(shell hostname) -e LOCAL_DOCKER_GID="" 
			# Default group id is '20' on macOS. This group id is already exsit on Linux Container. So set a same value as uid.
		else
			useropt=-e LOCAL_UID=$(shell id -u ${USER}) -e LOCAL_GID=$(shell id -g ${USER}) -e LOCAL_HOME=$(HOME) -e LOCAL_WHOAMI=$(shell whoami) -e LOCAL_HOSTNAME=$(shell hostname) -e LOCAL_DOCKER_GID=$(shell getent group docker | awk  -F: '{print $$3}')
		endif
		## wr
		useropt+= --mount type=bind,src=$(HOME)/work,dst=$(HOME)/work
		useropt+= --mount type=bind,src=$(HOME)/git,dst=$(HOME)/git
		useropt+= --mount type=bind,src=$(HOME)/.shared_cache,dst=$(HOME)/.shared_cache

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
		command=/usr/local/bin/exec_user.sh /bin/bash
	else
		useropt=-u `id -u`:`id -g` -e HOME=/tmphome
	endif
endif
ifneq ($(MOUNT), )
	mt= --mount type=bind,src=$(MOUNT),dst=$(MOUNT)
endif

ifneq ($(WK_DIR), )
	wkdir= -w $(WK_DIR)
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
	test -n "$(CONTAINER_ID)" || $(D) run --name $(NAME) -it $(useropt) $(rm) $(mt) $(wkdir) $(portopt) $(dopt) $(builder)/$(TGT):$(tag_opt) $(command)
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
