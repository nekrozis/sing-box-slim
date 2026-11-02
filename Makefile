SHELL := /bin/bash

SING_BOX_REF ?=
GO_VERSION ?=
PKGREL ?=
SING_BOX_SOURCE ?= sing-box
SING_BOX_VERSION ?=

.PHONY: source fetch build build-linux build-windows repro clean

source: $(SING_BOX_SOURCE)/.git

$(SING_BOX_SOURCE)/.git:
	@ref="$$(SING_BOX_REF='$(SING_BOX_REF)' ./scripts/resolve-version.sh SING_BOX_REF)" && \
	./scripts/fetch-sing-box.sh "$$ref" "$(SING_BOX_SOURCE)"

fetch:
	@ref="$$(SING_BOX_REF='$(SING_BOX_REF)' ./scripts/resolve-version.sh SING_BOX_REF)" && \
	./scripts/fetch-sing-box.sh "$$ref" "$(SING_BOX_SOURCE)"

build: build-linux build-windows

build-linux: source
	@go_version="$$(GO_VERSION='$(GO_VERSION)' ./scripts/resolve-version.sh GO_VERSION)" && \
	pkgrel="$$(PKGREL='$(PKGREL)' ./scripts/resolve-version.sh PKGREL)" && \
	GO_VERSION="$$go_version" PKGREL="$$pkgrel" TARGET_OS=linux SING_BOX_VERSION="$(SING_BOX_VERSION)" OUTPUT_DIR=dist/linux-amd64v3 ./scripts/build.sh

build-windows: source
	@go_version="$$(GO_VERSION='$(GO_VERSION)' ./scripts/resolve-version.sh GO_VERSION)" && \
	pkgrel="$$(PKGREL='$(PKGREL)' ./scripts/resolve-version.sh PKGREL)" && \
	GO_VERSION="$$go_version" PKGREL="$$pkgrel" TARGET_OS=windows SING_BOX_VERSION="$(SING_BOX_VERSION)" OUTPUT_DIR=dist/windows-amd64v3 ./scripts/build.sh

repro:
	./scripts/local-repro.sh

clean:
	rm -rf dist out
