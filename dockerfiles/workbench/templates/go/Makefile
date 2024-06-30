BINS=<binary's list>
PKG_NAME=<package's name>

TARGET=go
VERSION=$(shell curl -s https://raw.githubusercontent.com/hinoshiba/dockerfiles/master/version/$(TARGET)/strict)

OPT=-it --rm

MOUNT=--mount type=bind,src=$(CURDIR),dst=/src/ 
MOUNT+=--mount type=bind,src=$(HOME)/.ssh,dst=/root/.ssh,ro 
MOUNT+=--mount type=bind,src=$(HOME)/.gitconfig,dst=/root/.gitconfig,ro

D_HEAD=docker run $(OPT) $(MOUNT) $(TARGET):$(VERSION) /bin/bash -c "cd /src &&
D_TAIL= && chown $(shell id -u):$(shell id -g) -R ./*"

BUILD_FLGS= -buildvcs=false -tags netgo -installsuffix netgo -ldflags='-extldflags="static"'

SRCS := $(shell find . -name '*.go' -type f)
OUTPUT_PATH=./bin

.PHONY: help
help: ## help
	@awk -F ':|##' '/^[^\t].+?:.*?##/ {\
		printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
	}' $(MAKEFILE_LIST)

.PHONY: d-attach
d-attach: ## attach container
	@$(D_HEAD) /bin/bash $(D_TAIL)

.PHONY: all
all: d-test d-build

.PHONY: d-build
d-build:
	$(D_HEAD) make build $(D_TAIL)

.PHONY: d-mod
d-mod:
	$(D_HEAD) make mod $(D_TAIL)

.PHONY: d-modinit
d-modinit:
	$(D_HEAD) make modinit $(D_TAIL)

.PHONY: d-test
d-test:
	$(D_HEAD) make test $(D_TAIL)

.PHONY: d-clean
d-clean:
	$(D_HEAD) make clean $(D_TAIL)

.PHONY: build
build: $(BINS)

$(BINS): $(OUTPUT_PATH) $(SRCS)
	@echo -n "$@ building ..."
	go build $(BUILD_FLGS) -o ./bin/$(@) ./cmd/$(@)
	@echo "done"

.PHONY: mod
mod:
	go mod tidy
	go mod vendor

.PHONY: modinit
modinit:
	go mod init $(PKG_NAME)

.PHONY: test
test:
	go test -v -count=1 -timeout 30s ./...

.PHONY: clean
clean:
	go clean
	rm -rf $(OUTPUT_PATH)/*

$(OUTPUT_PATH):
	mkdir -p $(OUTPUT_PATH)
