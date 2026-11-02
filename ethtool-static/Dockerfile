ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG ETHTOOL_VERSION=7.2
ARG ETHTOOL_SHA256=44256ddf4631ed08d816b7b8725f4b2e0f05e96b8c7ca64ee5c81449da2b6507
ARG TARGETARCH
ARG JOBS=4

# libmnl-static 提供 netlink 接口所需的静态 libmnl；python3、bash 只用于测试。
RUN apk add --no-cache build-base linux-headers pkgconf libmnl-dev libmnl-static \
        curl xz file python3 bash

WORKDIR /build/ethtool
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/ethtool.tar.xz \
        "https://www.kernel.org/pub/software/network/ethtool/ethtool-${ETHTOOL_VERSION}.tar.xz" \
    && printf '%s  %s\n' "${ETHTOOL_SHA256}" /tmp/ethtool.tar.xz | sha256sum -c - \
    && tar -xJf /tmp/ethtool.tar.xz --strip-components=1

# 保留上游默认的 netlink 接口和寄存器/EEPROM/SFP 解析（pretty dump）。
# configure 要求 netlink 时找不到 libmnl 会直接失败，下面再检查 Makefile 确认两者都已启用。
RUN LDFLAGS="-static" ./configure --prefix=/usr --sbindir=/usr/sbin \
    && grep -q '^#define ETHTOOL_ENABLE_NETLINK 1' ethtool-config.h \
    && grep -q '^#define ETHTOOL_ENABLE_PRETTY_DUMP 1' ethtool-config.h \
    && grep -q '^MNL_LIBS = -lmnl' Makefile \
    && make -j"${JOBS}" \
    && make -j"${JOBS}" check \
    && mkdir -p /out \
    && cp ethtool /out/ethtool \
    && cp ethtool.8 /out/ethtool.8 \
    && cp shell-completion/bash/ethtool /out/ethtool.bash-completion \
    && cp COPYING /out/COPYING.ethtool \
    && strip /out/ethtool

RUN file /out/ethtool \
    && readelf -h /out/ethtool > /tmp/elf-header \
    && case "${TARGETARCH}" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && readelf -l /out/ethtool > /tmp/elf-program \
    && ! grep -q INTERP /tmp/elf-program \
    && readelf -d /out/ethtool > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/ethtool --version | tee /tmp/version \
    && grep -Fx "ethtool version ${ETHTOOL_VERSION}" /tmp/version

# 构建容器没有 CAP_NET_ADMIN，这里只做只读测试；修改类测试在宿主的独立网络命名空间中运行。
COPY test/smoke-test.py /build/smoke-test.py
RUN python3 /build/smoke-test.py /out

FROM scratch AS artifact
COPY --from=builder /out/ /
