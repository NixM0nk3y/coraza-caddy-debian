#!/bin/bash -e
#
# Extract the built .deb(s) out of the per-arch images into packages/<arch>/.
# Driven by the Makefile (post-build), which exports IMAGE/VERSION/ARCHES.
# Each arch was built+loaded as $IMAGE:$VERSION-<arch> by `make docker-build`.

: "${IMAGE:?set IMAGE (e.g. docker.io/nixm0nk3y/coraza-caddy-debian-arm)}"
: "${VERSION:?set VERSION}"
: "${ARCHES:=amd64 arm64}"

for arch in $ARCHES; do
    tag="${IMAGE}:${VERSION}-${arch}"
    dest="packages/${arch}"
    echo "==> extracting ${arch} from ${tag}"
    mkdir -p "${dest}"

    cid=$(docker run --detach --platform "linux/${arch}" "${tag}" /bin/sleep 60)
    # fpm leaves the .deb in /tmp; collect just the .deb(s) and copy them out
    docker exec "${cid}" bash -c 'mkdir -p /tmp/out && cp /tmp/*.deb /tmp/out/'
    docker cp "${cid}:/tmp/out/." "${dest}/"
    docker kill "${cid}" >/dev/null
    docker rm "${cid}" >/dev/null

    echo "    -> $(ls -1 "${dest}"/*.deb 2>/dev/null | tr '\n' ' ')"
done
