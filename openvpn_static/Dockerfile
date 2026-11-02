# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder

ARG OPENVPN_VERSION=2.6.21
ARG OPENVPN_SHA256=24cb6185e544a47323d6798b03d39f2367d96f227bee9cd1543e8ed528319b17

RUN apk add --no-cache \
        build-base \
        curl \
        file \
        libcap-ng-dev \
        libcap-ng-static \
        linux-headers \
        lz4-dev \
        lz4-static \
        lzo-dev \
        openssl-dev \
        openssl-libs-static \
        pkgconf \
        tar

WORKDIR /build

RUN curl --fail --location --retry 4 \
        --output openvpn.tar.gz \
        "https://build.openvpn.net/downloads/releases/openvpn-${OPENVPN_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${OPENVPN_SHA256}" openvpn.tar.gz | sha256sum -c - \
    && tar --extract --gzip --file openvpn.tar.gz --strip-components=1

# Keep features useful to a normal client while removing integrations which
# require loadable modules or additional host libraries.
RUN PKG_CONFIG="pkg-config --static" \
    CFLAGS="-Os -ffunction-sections -fdata-sections" \
    LDFLAGS="-static -Wl,--gc-sections" \
    ./configure \
        --disable-debug \
        --disable-dco \
        --disable-pkcs11 \
        --disable-plugins \
        --disable-shared \
        --disable-systemd \
        --disable-unit-tests \
        --enable-static \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
        LDFLAGS="-all-static -Wl,--gc-sections" \
    && strip src/openvpn/openvpn \
    && file src/openvpn/openvpn \
    && ! readelf -l src/openvpn/openvpn | grep -q 'interpreter' \
    && ! readelf -d src/openvpn/openvpn 2>&1 | grep -q '(NEEDED)'

FROM scratch AS artifact
COPY --from=builder /build/src/openvpn/openvpn /openvpn
