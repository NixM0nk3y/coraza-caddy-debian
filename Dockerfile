#
#
#

FROM debian:trixie

LABEL maintainer="Nick Gregory <docker@openenterprise.co.uk>"

ARG GOLANG_VERSION="1.26.3"
ARG GOLANG_SHA256="9d89a3ea57d141c2b22d70083f2c8459ba3890f2d9e818e7e933b75614936565"

ARG CADDY_VERSION="2.11.3"
ARG CORAZA_VERSION="2.5.0"

# basic build infra
RUN apt-get -y update \
    && apt-get -y dist-upgrade \
    && apt-get -y install curl build-essential cmake sudo wget git-core autoconf automake pkg-config quilt \
    && apt-get -y install ruby ruby-dev rubygems \
    && gem install --no-document fpm

RUN cd /tmp \
    && echo "==> Downloading Golang..." \
    && curl -fSL  https://go.dev/dl/go${GOLANG_VERSION}.linux-arm64.tar.gz -o go${GOLANG_VERSION}.linux-arm64.tar.gz \
    && sha256sum go${GOLANG_VERSION}.linux-arm64.tar.gz \
    && echo "${GOLANG_SHA256}  go${GOLANG_VERSION}.linux-arm64.tar.gz" | sha256sum -c - \
    && tar -C /usr/local -xzf /tmp/go${GOLANG_VERSION}.linux-arm64.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# package build
RUN go install -v github.com/caddyserver/xcaddy/cmd/xcaddy@latest \
    && CGO_ENABLED=1 /root/go/bin/xcaddy build v${CADDY_VERSION} \
    --output /tmp/caddy \
    --with github.com/corazawaf/coraza-caddy@v${CORAZA_VERSION}

# package install
RUN cd /tmp \
    && mkdir -p /install/var/www/html \
    && install -D -m 0755 /tmp/caddy /install/usr/bin/caddy \
    && fpm -s dir -t deb -C /install --name coraza-caddy --version ${CADDY_VERSION} --iteration 4 --depends "libpcre32-3" \
       --description "Caddy HTTP server with the coraza plugin built in"

STOPSIGNAL SIGTERM
