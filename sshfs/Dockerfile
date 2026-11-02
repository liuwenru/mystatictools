# syntax=docker/dockerfile:1
#
# sshfs 纯静态 (musl) 构建：sshfs + libfuse 工具 + OpenSSH 客户端。
# sshfs 运行时 execvp("ssh")，非 root 挂载依赖 setuid 的 fusermount3，
# 因此三者一起静态编译、一起分发。
#
#   docker buildx build --builder default --platform linux/amd64 \
#       --target artifact --output type=local,dest=dist/x86_64 .

ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION} AS builder

ARG SSHFS_VERSION=3.7.6
ARG SSHFS_SHA256=6a1bcb31450a077e9cb1b7ff158c71de34db697c3c0da6cb362502131e495893
ARG FUSE_VERSION=3.18.3
ARG FUSE_SHA256=bcd19582c5e30f7fe45dd86a5540e998590aa01903afc7ebcbeea6c8ac5421ee
ARG OPENSSH_VERSION=10.6p1
ARG OPENSSH_SHA256=a9dc9565dffe8640f64d863cd29a32bc4a3dbdec0566a7fc44c5d6ee767d5f39

RUN apk add --no-cache \
        build-base curl file linux-headers meson pkgconf \
        glib-dev glib-static pcre2-static gettext-static libffi-dev \
        liburing-dev numactl-dev \
        openssl-dev openssl-libs-static zlib-dev zlib-static

# 下载并校验源码，失败重试
RUN mkdir -p /src && cd /src \
    && curl --fail --location --retry 5 --retry-delay 3 -o sshfs.tar.xz \
        "https://github.com/libfuse/sshfs/releases/download/sshfs-${SSHFS_VERSION}/sshfs-${SSHFS_VERSION}.tar.xz" \
    && curl --fail --location --retry 5 --retry-delay 3 -o fuse.tar.gz \
        "https://github.com/libfuse/libfuse/releases/download/fuse-${FUSE_VERSION}/fuse-${FUSE_VERSION}.tar.gz" \
    && curl --fail --location --retry 5 --retry-delay 3 -o openssh.tar.gz \
        "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz" \
    && printf '%s  %s\n' \
        "${SSHFS_SHA256}" sshfs.tar.xz \
        "${FUSE_SHA256}" fuse.tar.gz \
        "${OPENSSH_SHA256}" openssh.tar.gz | sha256sum -c -

# libfuse：静态库 + fusermount3/mount.fuse3。
# prefix=/usr/local 决定 libfuse 优先调用 /usr/local/bin/fusermount3（失败再查 PATH）；
# sysconfdir=/etc 使 fusermount3 读取 /etc/fuse.conf。保留 io_uring 支持。
WORKDIR /build/fuse
RUN tar -xzf /src/fuse.tar.gz --strip-components=1 \
    && meson setup build \
        --prefix=/usr/local \
        --sysconfdir=/etc \
        --buildtype=release \
        --default-library=static \
        --prefer-static \
        -Dc_link_args=-static \
        -Dutils=true \
        -Dexamples=false \
        -Dtests=false \
        -Duseroot=false \
        -Dinitscriptdir= \
        -Dudevrulesdir=/tmp/udev-unused \
        -Denable-io-uring=true \
    && grep -q '^#define HAVE_URING' build/fuse_config.h \
    && meson compile -C build \
    && meson install -C build

# sshfs：静态链接 libfuse、glib（含 pcre2/intl）
WORKDIR /build/sshfs
RUN tar -xJf /src/sshfs.tar.xz --strip-components=1 \
    && meson setup build \
        --prefix=/usr/local \
        --buildtype=release \
        --prefer-static \
        -Dc_link_args=-static \
    && meson compile -C build

# OpenSSH 客户端：OpenSSL libcrypto + zlib（ssh -C / sshfs -C 压缩）。
# sysconfdir 用 prefix=/usr/local 时的上游默认值 /usr/local/etc/ssh，不读取
# /etc/ssh/ssh_config：RHEL/Fedora 系经 crypto-policies 引入发行版补丁选项
# （如 GSSAPIKexAlgorithms），上游 ssh 会报错退出。~/.ssh/config 照常读取。
WORKDIR /build/openssh
RUN tar -xzf /src/openssh.tar.gz --strip-components=1 \
    && ./configure \
        --prefix=/usr/local \
        --sysconfdir=/usr/local/etc/ssh \
        --with-ldflags=-static \
        --without-pie \
        --with-ssl-dir=/usr \
        --with-zlib \
        --without-pam \
        --without-kerberos5 \
        --without-libedit \
        --without-selinux \
        > /tmp/openssh-configure.log \
    && sed -n '/OpenSSH has been configured/,$p' /tmp/openssh-configure.log \
    && make -j"$(getconf _NPROCESSORS_ONLN)" ssh ssh-keygen ssh-add ssh-agent ssh-keyscan

RUN mkdir -p /out \
    && cp /build/sshfs/build/sshfs /out/ \
    && cp /build/fuse/build/util/fusermount3 /build/fuse/build/util/mount.fuse3 /out/ \
    && cd /build/openssh && cp ssh ssh-keygen ssh-add ssh-agent ssh-keyscan /out/ \
    && cd /out && strip * \
    && for f in *; do \
        file "$f"; \
        ! readelf -lW "$f" | grep -q INTERP || { echo "$f: has INTERP" >&2; exit 1; }; \
        ! readelf -dW "$f" 2>&1 | grep -q '(NEEDED)' || { echo "$f: has NEEDED" >&2; exit 1; }; \
    done \
    && sha256sum * > /SHA256SUMS && mv /SHA256SUMS /out/

# 在没有任何共享库的根文件系统中验证版本（只有静态 busybox 用作 shell）
FROM alpine:${ALPINE_VERSION} AS busybox
RUN apk add --no-cache busybox-static

FROM scratch AS check
ARG SSHFS_VERSION=3.7.6
ARG FUSE_VERSION=3.18.3
ARG OPENSSH_VERSION=10.6p1
COPY --from=busybox /bin/busybox.static /bin/busybox
COPY --from=builder /out/ /usr/local/bin/
RUN ["/bin/busybox", "sh", "-c", "/bin/busybox --install -s /bin && mkdir -m 1777 /tmp && mkdir -p /etc /root && echo root:x:0:0:root:/root:/bin/sh > /etc/passwd && echo root:x:0: > /etc/group"]
ENV PATH=/usr/local/bin:/bin
RUN set -e; test ! -e /lib/ld-musl-*; \
    sshfs --version 2>&1 | tee /tmp/v; \
    grep -qx "SSHFS version ${SSHFS_VERSION}" /tmp/v; \
    grep -qx "FUSE library version ${FUSE_VERSION}" /tmp/v; \
    grep -q "fusermount3 version: ${FUSE_VERSION}" /tmp/v; \
    { mount.fuse3 2>&1 || true; } | grep -q "^usage: mount.fuse3"; \
    ssh -V 2>&1 | tee /tmp/s; grep -q "OpenSSH_${OPENSSH_VERSION}" /tmp/s; \
    ssh -Q cipher | grep -qx chacha20-poly1305@openssh.com; \
    ssh -Q cipher | grep -qx aes256-gcm@openssh.com; \
    ssh -Q kex | grep -q mlkem768x25519-sha256; \
    mkdir -p /etc/ssh && echo 'GSSAPIKexAlgorithms gss-group14-sha256-' > /etc/ssh/ssh_config; \
    ssh -G example.invalid | grep -qx 'user root'; rm -r /etc/ssh; \
    ssh-keygen -q -t ed25519 -N '' -f /tmp/k && ssh-keygen -l -f /tmp/k.pub; \
    ssh-keygen -q -t rsa -b 2048 -N '' -f /tmp/r && ssh-keygen -l -f /tmp/r.pub; \
    ssh-keygen -q -t ecdsa -N '' -f /tmp/e && ssh-keygen -l -f /tmp/e.pub

# 从 check 阶段导出，保证检查通过后才有产物
FROM scratch AS artifact
COPY --from=check /usr/local/bin/ /
