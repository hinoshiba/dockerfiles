D=docker

TGT=${target}
ARGS=${args}
MOUNT=${mount}

SRCS := $(shell find . -type f)
export http_proxy
export https_proxy

all: build run ## exec "build" and "run"
build: $(SRCS) ## build to all container
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
ifeq ($(http_proxy), )
ifeq ($(https_proxy), )
	$(D) image build -t $(TGT) $(TGT)/.
else
	$(D) image build --build-arg https_proxy=$(https_proxy) -t $(TGT) $(TGT)/.
endif
else
ifeq ($(https_proxy), )
	$(D) image build --build-arg http_proxy=$(http_proxy) -t $(TGT) $(TGT)/.
else
	$(D) image build --build-arg http_proxy=$(http_proxy) --build-arg https_proxy=$(https_proxy) -t $(TGT) $(TGT)/.
endif
endif

run: $(SRCS) ## start up to all container
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
ifeq ($(MOUNT), )
#	$(D) run -u `id -u`:`id -g` --name $(TGT) --rm -it $(ARGS) $(TGT) /bin/bash
	$(D) run --name $(TGT) --rm -it $(ARGS) $(TGT) /bin/bash
else
#	$(D) run -u `id -u`:`id -g` --name $(TGT) --rm -it --mount type=bind,src=$(MOUNT),dst=$(MOUNT) $(ARGS) $(TGT) /bin/bash
	$(D) run --name $(TGT) --rm -it --mount type=bind,src=$(MOUNT),dst=$(MOUNT) $(ARGS) $(TGT) /bin/bash
endif

stop: $(SRCS) ## down to container
ifeq ($(TGT), )
	@echo "not set target. usage: make <operation> target=<your target>"
	@exit 1
endif
	$(D) stop $(TGT)

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
	$(D) rmi $(TGT)

.PHONY: help
	all: help
help: ## help
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
	}' $(MAKEFILE_LIST)
