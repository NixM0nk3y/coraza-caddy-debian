#
#   Copyright 2015  Xebia Nederland B.V.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
REGISTRY_HOST=docker.io
USERNAME=nixm0nk3y
NAME=coraza-caddy-debian-arm

RELEASE_SUPPORT := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))/.make-release-support
IMAGE=$(REGISTRY_HOST)/$(USERNAME)/$(NAME)

VERSION=$(shell . $(RELEASE_SUPPORT) ; getVersion)
TAG=$(shell . $(RELEASE_SUPPORT); getTag)

SHELL=/bin/bash

DOCKER_BUILD_CONTEXT=.
DOCKER_FILE_PATH=Dockerfile

# Multi-arch build (buildx). ARCHES is space-separated; each is built with
# `--load` so the .deb can be extracted locally, then published as one
# manifest list on push.
ARCHES ?= amd64 arm64
BUILDX_BUILDER ?= oe-multiarch

.PHONY: pre-build docker-build post-build build release patch-release minor-release major-release tag check-status check-release showver \
	push pre-push do-push post-push buildx-setup

build: pre-build docker-build post-build

pre-build: buildx-setup

# Ensure a docker-container buildx builder + cross-arch emulation (binfmt)
# exist, so e.g. an arm64 host can build the amd64 image and vice-versa.
buildx-setup:
	@docker buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1 || \
		docker buildx create --name $(BUILDX_BUILDER) --driver docker-container --bootstrap
	@docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true

post-build:
	@IMAGE=$(IMAGE) VERSION=$(VERSION) ARCHES="$(ARCHES)" ./extractdeb.sh

pre-push:


post-push:



docker-build: .release buildx-setup
	@for arch in $(ARCHES); do \
		echo "==> buildx build linux/$$arch"; \
		docker buildx build --builder $(BUILDX_BUILDER) $(DOCKER_BUILD_ARGS) \
			--platform linux/$$arch --load \
			-t $(IMAGE):$(VERSION)-$$arch -t $(IMAGE):latest-$$arch \
			$(DOCKER_BUILD_CONTEXT) -f $(DOCKER_FILE_PATH) || exit 1; \
	done

.release:
	@echo "release=0.0.0" > .release
	@echo "tag=$(NAME)-0.0.0" >> .release
	@echo INFO: .release created
	@cat .release


release: check-status check-release build push


push: pre-push do-push post-push 

do-push:
	@for arch in $(ARCHES); do \
		docker push $(IMAGE):$(VERSION)-$$arch; \
		docker push $(IMAGE):latest-$$arch; \
	done
	docker manifest rm $(IMAGE):$(VERSION) 2>/dev/null || true
	docker manifest create $(IMAGE):$(VERSION) $(foreach a,$(ARCHES),$(IMAGE):$(VERSION)-$(a))
	docker manifest push $(IMAGE):$(VERSION)
	docker manifest rm $(IMAGE):latest 2>/dev/null || true
	docker manifest create $(IMAGE):latest $(foreach a,$(ARCHES),$(IMAGE):latest-$(a))
	docker manifest push $(IMAGE):latest

snapshot: build push

showver: .release
	@. $(RELEASE_SUPPORT); getVersion

tag-patch-release: VERSION := $(shell . $(RELEASE_SUPPORT); nextPatchLevel)
tag-patch-release: .release tag 

tag-minor-release: VERSION := $(shell . $(RELEASE_SUPPORT); nextMinorLevel)
tag-minor-release: .release tag 

tag-major-release: VERSION := $(shell . $(RELEASE_SUPPORT); nextMajorLevel)
tag-major-release: .release tag 

patch-release: tag-patch-release release
	@echo $(VERSION)

minor-release: tag-minor-release release
	@echo $(VERSION)

major-release: tag-major-release release
	@echo $(VERSION)


tag: TAG=$(shell . $(RELEASE_SUPPORT); getTag $(VERSION))
tag: check-status
	@. $(RELEASE_SUPPORT) ; ! tagExists $(TAG) || (echo "ERROR: tag $(TAG) for version $(VERSION) already tagged in git" >&2 && exit 1) ;
	@. $(RELEASE_SUPPORT) ; setRelease $(VERSION)
	git add .
	git commit -m "bumped to version $(VERSION)" ;
	git tag $(TAG) ;
	@ if [ -n "$(shell git remote -v)" ] ; then git push --tags ; else echo 'no remote to push tags to' ; fi

check-status:
	@. $(RELEASE_SUPPORT) ; ! hasChanges || (echo "ERROR: there are still outstanding changes" >&2 && exit 1) ;

check-release: .release
	@. $(RELEASE_SUPPORT) ; tagExists $(TAG) || (echo "ERROR: version not yet tagged in git. make [minor,major,patch]-release." >&2 && exit 1) ;
	@. $(RELEASE_SUPPORT) ; ! differsFromRelease $(TAG) || (echo "ERROR: current directory differs from tagged $(TAG). make [minor,major,patch]-release." ; exit 1)
