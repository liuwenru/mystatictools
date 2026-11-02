# syntax=docker/dockerfile:1.6
#
# ipvsadm — fully static (musl) build, multi-arch capable.
#
# Usage:
#   docker buildx build --builder default --platform linux/amd64 -t ipvsadm:dev --load .
#   docker buildx build --builder default --platform linux/arm64 -t ipvsadm:arm64 --load .
#
# Output binary is in /usr/sbin/ipvsadm (+ ipvsadm-save / ipvsadm-restore).

ARG ALPINE_VERSION=3.20

# ----------------------------------------------------------------------------
# Stage 1 — build popt & libnl statically into /opt/static
# ----------------------------------------------------------------------------
FROM --platform=$TARGETPLATFORM alpine:${ALPINE_VERSION} AS deps

ARG POPT_VERSION=1.19
ARG LIBNL_VERSION=3.7.0

RUN apk add --no-cache \
        build-base \
        autoconf \
        automake \
        libtool \
        pkgconf \
        gettext-dev \
        bison \
        flex \
        linux-headers

# popt
ARG POPT_URL=https://github.com/rpm-software-management/popt/archive/refs/tags/popt-${POPT_VERSION}-release.tar.gz
ARG POPT_SHA256=6eb40d650526cb9fe63eb4415bcecdf9cf306f7556e77eff689abc5a44670060
ADD --checksum=sha256:${POPT_SHA256} ${POPT_URL} /tmp/popt.tar.gz
RUN tar -xzf /tmp/popt.tar.gz -C /tmp \
 && cd /tmp/popt-popt-${POPT_VERSION}-release \
 && ./autogen.sh --prefix=/opt/static \
 && ./configure --prefix=/opt/static \
                --enable-static \
                --disable-shared \
                --disable-nls \
 && make -j"$(nproc)" \
 && make install \
 && rm -rf /tmp/popt-popt-${POPT_VERSION}-release /tmp/popt.tar.gz

# libnl
ARG LIBNL_TARBALL=libnl-3.7.0.tar.gz
ARG LIBNL_URL=https://github.com/thom311/libnl/releases/download/libnl3_7_0/${LIBNL_TARBALL}
ARG LIBNL_SHA256=9fe43ccbeeea72c653bdcf8c93332583135cda46a79507bfd0a483bb57f65939
ADD --checksum=sha256:${LIBNL_SHA256} ${LIBNL_URL} /tmp/libnl.tar.gz
RUN tar -xzf /tmp/libnl.tar.gz -C /tmp \
 && cd /tmp/libnl-${LIBNL_VERSION} \
 && ./configure --prefix=/opt/static \
                --enable-static \
                --disable-shared \
                --disable-cli \
 && make -j"$(nproc)" \
 && make install \
 && rm -rf /tmp/libnl-${LIBNL_VERSION} /tmp/libnl.tar.gz

# ----------------------------------------------------------------------------
# Stage 2 — build ipvsadm against /opt/static, producing a fully static binary
# ----------------------------------------------------------------------------
FROM --platform=$TARGETPLATFORM alpine:${ALPINE_VERSION} AS builder

ARG IPVSADM_VERSION=1.31
ARG IPVSADM_URL=https://mirrors.kernel.org/pub/linux/utils/kernel/ipvsadm/ipvsadm-${IPVSADM_VERSION}.tar.gz
ARG IPVSADM_SHA256=7276bcf214f31051188b2e44f11029e57303f37e54126e517000c1b2123a6d4e

COPY --from=deps /opt/static /opt/static

RUN apk add --no-cache \
        build-base \
        binutils \
        linux-headers \
        pkgconf

ADD --checksum=sha256:${IPVSADM_SHA256} ${IPVSADM_URL} /tmp/ipvsadm.tar.gz
RUN tar -xzf /tmp/ipvsadm.tar.gz -C /tmp \
 && cd /tmp/ipvsadm-${IPVSADM_VERSION} \
 && export PKG_CONFIG_PATH=/opt/static/lib/pkgconfig \
 && NL_CFLAGS="$(pkg-config --cflags libnl-genl-3.0)" \
 && make HAVE_NL=1 \
         SHARED_LIB= \
         CFLAGS="-Wall -Wunused -Wstrict-prototypes -O2 \
                 -static -static-libgcc \
                 -include sys/types.h \
                 -I/opt/static/include \
                 ${NL_CFLAGS}" \
         LDFLAGS="-L/opt/static/lib" \
 && strip ipvsadm \
 && readelf -lW ipvsadm > /tmp/ipvsadm.program-headers \
 && readelf -dW ipvsadm > /tmp/ipvsadm.dynamic \
 && ! grep -q INTERP /tmp/ipvsadm.program-headers \
 && ! grep -q NEEDED /tmp/ipvsadm.dynamic \
 && mkdir -p /out \
 && cp -a ipvsadm /out/ \
 && cp -a ipvsadm-save ipvsadm-restore /out/ \
 && chmod +x /out/ipvsadm-save /out/ipvsadm-restore \
 && rm -rf /tmp/ipvsadm-${IPVSADM_VERSION} /tmp/ipvsadm.tar.gz

# ----------------------------------------------------------------------------
# Stage 3 — runtime image (Bash and BusyBox for upstream helper scripts)
# ----------------------------------------------------------------------------
FROM --platform=$TARGETPLATFORM alpine:${ALPINE_VERSION} AS runtime

RUN apk add --no-cache bash

COPY --from=builder /out/ipvsadm          /usr/sbin/ipvsadm
COPY --from=builder /out/ipvsadm-save     /usr/sbin/ipvsadm-save
COPY --from=builder /out/ipvsadm-restore  /usr/sbin/ipvsadm-restore

# Only ipvsadm is an ELF binary; save/restore are upstream Bash scripts.
RUN ldd /usr/sbin/ipvsadm 2>&1 | grep -q "Not a valid dynamic program" \
 && bash -n /usr/sbin/ipvsadm-save \
 && bash -n /usr/sbin/ipvsadm-restore \
 && command -v grep && command -v basename \
 && echo "OK: static ipvsadm and Bash helper scripts"

ENTRYPOINT ["/usr/sbin/ipvsadm"]
CMD ["--help"]
