# syntax=docker/dockerfile:1
# 参照 nodejs/unofficial-builds recipes/musl（Alpine 3.23 原生编译），
# 额外加 --fully-static；两种架构都在各自原生主机上编译，不用 arm64-musl 的交叉配方。
ARG ALPINE_VERSION=3.23
FROM alpine:${ALPINE_VERSION} AS builder
ARG NODE_VERSION=26.13.0
ARG NODE_SHA256=263f639ecfa7a17b49438d76cdbf9aff73179e3c7cb789da69b900718427fa2e
ARG BUILD_JOBS=16
ARG TARGETARCH

# rust/cargo：Node 26 的 Temporal 由 temporal_rs 提供，缺少时 configure 会静默关闭 Temporal，
# 这里用 --v8-enable-temporal-support 强制要求。crate 已随源码 vendor，编译时 cargo 不联网。
RUN apk add --no-cache bash binutils curl file g++ gcc linux-headers make python3 xz \
      rust cargo openssl

WORKDIR /build
RUN curl -fL --retry 4 --retry-all-errors -o /build/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.xz" \
    && echo "${NODE_SHA256}  /build/node.tar.xz" | sha256sum -c - \
    && xz -dc /build/node.tar.xz | tar -x -C /build \
    && mv "/build/node-v${NODE_VERSION}" /build/node

# 与 Makefile 的 binary 目标步骤相同（configure --prefix=/、make install PORTABLE=1、复制说明文件），
# 只是不在容器里打 tar 包。full-icu 数据已在源码包中，不使用 --download=all。
WORKDIR /build/node
RUN case "${TARGETARCH}" in \
        amd64) dest_cpu=x64 ;; \
        arm64) dest_cpu=arm64 ;; \
        *) echo "不支持的架构: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && ./configure --prefix=/ --dest-cpu="${dest_cpu}" --fully-static \
         --with-intl=full-icu --v8-enable-temporal-support \
    && make -j"${BUILD_JOBS}" V= \
    && make install DESTDIR=/out/node PORTABLE=1 V= \
    && cp README.md LICENSE CHANGELOG.md /out/node/ \
    && strip /out/node/bin/node \
    && file /out/node/bin/node \
    && case "${TARGETARCH}" in \
        amd64) readelf -h /out/node/bin/node | grep -q 'Machine:.*X86-64' ;; \
        arm64) readelf -h /out/node/bin/node | grep -q 'Machine:.*AArch64' ;; \
    esac \
    && readelf -lW /out/node/bin/node > /tmp/elf-program-headers \
    && ! grep -q INTERP /tmp/elf-program-headers \
    && readelf -dW /out/node/bin/node > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/node/bin/node --version | grep -Fx "v${NODE_VERSION}" \
    && printf 'node v%s\nsource https://nodejs.org/dist/v%s/node-v%s.tar.xz\nsha256 %s\nconfigure --fully-static --with-intl=full-icu --v8-enable-temporal-support\nalpine %s\n' \
         "${NODE_VERSION}" "${NODE_VERSION}" "${NODE_VERSION}" "${NODE_SHA256}" "$(cat /etc/alpine-release)" \
         > /out/node/BUILD-INFO.txt

# 测试用资料，不进入运行包：TLS 自签证书、一个最小 N-API 原生扩展（用于确认静态版无法加载 .node）、
# 一个本地 npm 包（用于验证 npm 离线安装本地包）。
COPY test/ /build/test/
RUN mkdir -p /fixtures/addon /fixtures/local-pkg \
    && openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=localhost \
         -addext subjectAltName=DNS:localhost,IP:127.0.0.1 \
         -keyout /fixtures/key.pem -out /fixtures/cert.pem 2>/dev/null \
    && gcc -shared -fPIC -I/out/node/include/node -o /fixtures/addon/hello.node /build/test/hello-addon.c \
    && cp /build/test/local-pkg/* /fixtures/local-pkg/ \
    && /out/node/bin/node /build/test/smoke-test.js "v${NODE_VERSION}" /fixtures

# 空根文件系统 + 断网：没有 /bin/sh、libc、证书、/etc/hosts，只有 node 和测试资料。
FROM scratch AS offline-test
ARG NODE_VERSION=26.13.0
COPY --from=builder /out/node /node
COPY --from=builder /build/test/smoke-test.js /tests/smoke-test.js
COPY --from=builder /fixtures /fixtures
ENV PATH=/node/bin HOME=/test/home TMPDIR=/test/tmp NODE_EXPECTED_VERSION=v${NODE_VERSION}
WORKDIR /test/tmp
WORKDIR /test/home
RUN --network=none ["/node/bin/node", "/tests/smoke-test.js", "", "/fixtures"]
RUN ["/node/bin/node", "-e", "require('fs').writeFileSync('/test/offline-test.ok', 'ok\\n')"]

FROM scratch AS artifact
COPY --from=builder /out/node /node
# 引用 offline-test 的结果，保证导出前 scratch 测试已执行。
COPY --from=offline-test /test/offline-test.ok /node-offline-test.ok
