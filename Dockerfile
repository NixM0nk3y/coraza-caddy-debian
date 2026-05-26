# syntax=docker/dockerfile:1
#
# Multi-arch (amd64 + arm64) build of the coraza-caddy .deb — Caddy with the
# Coraza WAF compiled in (xcaddy).
#
# The Go toolchain + the resulting .deb architecture follow the *container's
# own* arch (dpkg), so the build is internally consistent whether run as a
# plain `docker build` (native arch) or `docker buildx --platform` (emulated
# arch) — this avoids the cgo `-m64`/arch-mismatch trap. The amd64 build is
# what fizzgig needs for the hosting web tier (prod-upgrade.md §3.3/§4.5);
# arm64 serves the home estate.
#
# For a cross-arch build (e.g. amd64 on an arm64 host) use buildx with QEMU
# emulation — `make build` sets that up (buildx-setup) and builds each arch.
#

FROM debian:trixie

LABEL maintainer="Nick Gregory <docker@openenterprise.co.uk>"

ARG GOLANG_VERSION="1.26.3"
# Per-arch checksum for go${GOLANG_VERSION}.linux-<arch>.tar.gz.
# Refresh both on a Go bump: https://go.dev/dl/?mode=json&include=all
ARG GOLANG_SHA256_amd64="2b2cfc7148493da5e73981bffbf3353af381d5f93e789c82c79aff64962eb556"
ARG GOLANG_SHA256_arm64="9d89a3ea57d141c2b22d70083f2c8459ba3890f2d9e818e7e933b75614936565"

ARG CADDY_VERSION="2.11.3"
ARG CORAZA_VERSION="2.5.0"

# basic build infra
RUN apt-get -y update \
    && apt-get -y dist-upgrade \
    && apt-get -y install curl build-essential cmake sudo wget git-core autoconf automake pkg-config quilt \
    && apt-get -y install ruby ruby-dev rubygems \
    && gem install --no-document fpm

# Go toolchain — arch + pinned checksum from the CONTAINER's own arch (dpkg),
# so the Go target always matches the in-container C toolchain (no cgo -m64
# mismatch). Works for plain `docker build` and buildx --platform alike.
RUN cd /tmp \
    && ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in \
         amd64) GOLANG_SHA256="${GOLANG_SHA256_amd64}" ;; \
         arm64) GOLANG_SHA256="${GOLANG_SHA256_arm64}" ;; \
         *) echo "unsupported arch '${ARCH}'" >&2; exit 1 ;; \
       esac \
    && echo "==> Downloading Go ${GOLANG_VERSION} for linux-${ARCH}..." \
    && curl -fSL "https://go.dev/dl/go${GOLANG_VERSION}.linux-${ARCH}.tar.gz" -o go.tar.gz \
    && echo "${GOLANG_SHA256}  go.tar.gz" | sha256sum -c - \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# package build — xcaddy compiles Caddy + the Coraza module natively for the
# container arch (CGO; runs under QEMU when the container is emulated)
RUN go install -v github.com/caddyserver/xcaddy/cmd/xcaddy@latest \
    && CGO_ENABLED=1 /root/go/bin/xcaddy build v${CADDY_VERSION} \
    --output /tmp/caddy \
    --with github.com/corazawaf/coraza-caddy@v${CORAZA_VERSION}

# package install — fpm tags the .deb with the container's arch (dpkg)
RUN cd /tmp \
    && mkdir -p /install/var/www/html \
    && install -D -m 0755 /tmp/caddy /install/usr/bin/caddy \
    && fpm -s dir -t deb -C /install --name coraza-caddy \
       --version ${CADDY_VERSION} --iteration 1 \
       --architecture "$(dpkg --print-architecture)" \
       --description "Caddy HTTP server with the coraza plugin built in"

STOPSIGNAL SIGTERM
