ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG TREE_VERSION=2.3.2
ARG TREE_SHA256=6b941dd6cbecfb4d3250700e4d08d8e0c251488981dd4868b90d744234300e21
ARG TARGETARCH
ARG JOBS=4

# tree 只依赖 libc；--acl、--selinux 直接调用 listxattr/getxattr，不需要 libacl、libselinux。
RUN apk add --no-cache build-base curl file python3
WORKDIR /build
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/tree.tgz \
        "https://oldmanprogrammer.net/tar/tree/tree-${TREE_VERSION}.tgz" \
    && printf '%s  %s\n' "${TREE_SHA256}" /tmp/tree.tgz | sha256sum -c - \
    && tar -xzf /tmp/tree.tgz
WORKDIR /build/tree-${TREE_VERSION}
# 使用官方 Makefile 的 Linux 默认配置，只通过环境变量指定优化级别和静态链接。
RUN CFLAGS=-O2 LDFLAGS=-static make -j"${JOBS}" \
    && mkdir -p /out \
    && cp tree doc/tree.1 doc/global_info LICENSE /out/ \
    && strip /out/tree \
    && file /out/tree \
    && readelf -h /out/tree > /tmp/elf-header \
    && case "${TARGETARCH}" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && readelf -l /out/tree > /tmp/elf-program \
    && ! grep -q INTERP /tmp/elf-program \
    && readelf -d /out/tree > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/tree --version | tee /tmp/version \
    && grep -F "tree v${TREE_VERSION} " /tmp/version

COPY test/smoke-test.py /build/smoke-test.py
RUN python3 /build/smoke-test.py /out/tree

FROM scratch AS artifact
COPY --from=builder /out/ /
