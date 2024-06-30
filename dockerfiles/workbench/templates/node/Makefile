TARGET=node
VERSION=$(shell curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/$(TARGET)/strict)

OPT=-it --rm

MOUNT=--mount type=bind,src=$(CURDIR),dst=/src/ 
MOUNT+=--mount type=bind,src=$(HOME)/.ssh,dst=/root/.ssh,ro 
MOUNT+=--mount type=bind,src=$(HOME)/.gitconfig,dst=/root/.gitconfig,ro

D_HEAD=docker run $(OPT) $(MOUNT) $(TARGET):$(VERSION) /bin/bash -c "cd /src &&
D_TAIL= && chown $(shell id -u):$(shell id -g) -R ./*"

.PHONY: help
help: ## help
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
	}' $(MAKEFILE_LIST)

.PHONY: d-attach
d-attach: ## attach container
	@$(D_HEAD) /bin/bash $(D_TAIL)
