SHELL := /bin/bash

SING_BOX_REF ?= v1.14.4
SING_BOX_SOURCE ?= sing-box
SING_BOX_VERSION ?=

.PHONY: source fetch build build-linux build-windows repro clean

source: $(SING_BOX_SOURCE)/.git

$(SING_BOX_SOURCE)/.git:
	./scripts/fetch-sing-box.sh "$(SING_BOX_REF)" "$(SING_BOX_SOURCE)"

fetch:
	./scripts/fetch-sing-box.sh "$(SING_BOX_REF)" "$(SING_BOX_SOURCE)"

build: build-linux build-windows

build-linux: source
	TARGET_OS=linux SING_BOX_VERSION="$(SING_BOX_VERSION)" OUTPUT_DIR=dist/linux-amd64v3 ./scripts/build.sh

build-windows: source
	TARGET_OS=windows SING_BOX_VERSION="$(SING_BOX_VERSION)" OUTPUT_DIR=dist/windows-amd64v3 ./scripts/build.sh

repro: source
	./scripts/local-repro.sh

clean:
	rm -rf dist out
