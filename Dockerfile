# syntax=docker/dockerfile:1
#
# Multi-arch (amd64 + arm64) build of the coraza-caddy .deb — Caddy with the
# Coraza WAF compiled in (xcaddy).
#
# buildx populates TARGETARCH (amd64|arm64); the base image, the Go toolchain
# tarball, and the resulting .deb architecture all follow it. The amd64 build
# is what fizzgig needs for the hosting web tier (prod-upgrade.md §3.3/§4.5);
# arm64 serves the home estate.
#
# Build per-arch with `--load` (see the Makefile), or directly:
#   docker buildx build --platform linux/amd64 --load -t coraza-caddy:amd64 .
#

FROM debian:trixie

LABEL maintainer="Nick Gregory <docker@openenterprise.co.uk>"

# Provided automatically by buildx (amd64 | arm64). Default keeps a bare
# `docker build` working on an amd64 host.
ARG TARGETARCH=amd64

ARG GOLANG_VERSION="1.26.3"
# Per-arch checksum for go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz.
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

# Go toolchain — arch + pinned checksum selected from TARGETARCH
RUN cd /tmp \
    && case "${TARGETARCH}" in \
         amd64) GOLANG_SHA256="${GOLANG_SHA256_amd64}" ;; \
         arm64) GOLANG_SHA256="${GOLANG_SHA256_arm64}" ;; \
         *) echo "unsupported TARGETARCH='${TARGETARCH}'" >&2; exit 1 ;; \
       esac \
    && echo "==> Downloading Go ${GOLANG_VERSION} for linux-${TARGETARCH}..." \
    && curl -fSL "https://go.dev/dl/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz" -o go.tar.gz \
    && echo "${GOLANG_SHA256}  go.tar.gz" | sha256sum -c - \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# package build — xcaddy compiles Caddy + the Coraza module for the target
# arch (CGO under emulation when cross-building)
RUN go install -v github.com/caddyserver/xcaddy/cmd/xcaddy@latest \
    && CGO_ENABLED=1 /root/go/bin/xcaddy build v${CADDY_VERSION} \
    --output /tmp/caddy \
    --with github.com/corazawaf/coraza-caddy@v${CORAZA_VERSION}

# package install — fpm tags the .deb with the target arch (dpkg reports the
# emulated/native container arch, i.e. TARGETARCH)
RUN cd /tmp \
    && mkdir -p /install/var/www/html \
    && install -D -m 0755 /tmp/caddy /install/usr/bin/caddy \
    && fpm -s dir -t deb -C /install --name coraza-caddy \
       --version ${CADDY_VERSION} --iteration 1 \
       --architecture "$(dpkg --print-architecture)" \
       --description "Caddy HTTP server with the coraza plugin built in"

STOPSIGNAL SIGTERM
