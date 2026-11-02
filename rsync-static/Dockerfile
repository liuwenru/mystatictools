ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG RSYNC_VERSION=3.5.1
ARG RSYNC_SHA256=c55f9c9dc10fb8bec397b399a0fdded53cc9a2d8e30891bb0d63724d25c37bef
ARG XXHASH_VERSION=0.8.3
ARG XXHASH_SHA256=aae608dfe8213dfd05d909a57718ef82f30722c392344583d3f39050c7f29a80
ARG LIBICONV_VERSION=1.19.1
ARG LIBICONV_SHA256=9a06844846d664d7122161700c10a64480d7c7bcead3091925a785b38c91edab
ARG TARGETARCH
ARG JOBS=4

# 静态库来自 Alpine；xxhash、GNU libiconv 在 Alpine 没有静态库，下面从源码构建。
# python3 运行上游测试和 smoke 测试；acl/attr 提供 setfacl/setfattr，bash 运行 rsync-ssl 脚本测试，
# setpriv（util-linux 版，BusyBox 版缺 --reuid）用于降权测试；
# rsync 包是 Alpine 自带的旧版本，只用于测试与旧版本互通，不进运行包。
RUN apk add --no-cache build-base linux-headers curl file python3 bash setpriv \
        acl acl-dev acl-static attr popt-dev popt-static \
        zstd-dev zstd-static lz4-dev lz4-static openssl-dev openssl-libs-static \
        libidn2-dev libidn2-static libunistring-dev libunistring-static \
        rsync

WORKDIR /build/xxhash
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/xxhash.tar.gz \
        "https://github.com/Cyan4973/xxHash/archive/refs/tags/v${XXHASH_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${XXHASH_SHA256}" /tmp/xxhash.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/xxhash.tar.gz --strip-components=1
# 只装静态库和头文件到 /usr/local；不装 xxhash-dev，避免头文件与库版本不一致。
RUN make -j"${JOBS}" libxxhash.a \
    && mkdir -p /usr/local/lib /usr/local/include \
    && cp libxxhash.a /usr/local/lib/ \
    && cp xxhash.h xxh3.h /usr/local/include/

# --iconv 需要文件名编码双向转换。musl iconv 对 GBK/GB18030/BIG5 只能解码不能编码，rsync 同时打开两个方向，
# 遇到 GBK 直接报 iconv_open failed。GNU libiconv 的转换表编译在库内，静态链接后不依赖 gconv 等数据文件。
WORKDIR /build/libiconv
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/libiconv.tar.gz \
        "https://ftp.gnu.org/gnu/libiconv/libiconv-${LIBICONV_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${LIBICONV_SHA256}" /tmp/libiconv.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/libiconv.tar.gz --strip-components=1
RUN ./configure --prefix=/usr/local --enable-static --disable-shared --disable-nls \
    && make -j"${JOBS}" \
    && make install

WORKDIR /build/rsync
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/rsync.tar.gz \
        "https://github.com/RsyncProject/rsync/releases/download/v${RSYNC_VERSION}/rsync-${RSYNC_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${RSYNC_SHA256}" /tmp/rsync.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/rsync.tar.gz --strip-components=1
# --with-openssl-conf=/dev/null：静态 OpenSSL 不能加载目标机 openssl.cnf 引用的 provider 模块，
#   不读目标机配置；MD4 等 legacy 摘要由 rsync 内置实现，结果相同。环境变量 OPENSSL_CONF 仍可覆盖。
# zlib 用 rsync 自带的（上游默认），保证 -z 与旧版本 rsync 兼容。
# libidn2 静态链接需要在末尾补 libunistring。/usr/local/include 中 GNU libiconv 的 iconv.h 先于 musl 的被找到，
#   iconv_open 等被宏替换为 libiconv_open，configure 自动加 -liconv；链接后用 nm 确认。
# x86_64 滚动校验 SIMD（USE_ROLL_SIMD）依赖 GCC 函数多版本（IFUNC），musl 工具链不支持，configure 自动关闭；
#   只影响弱校验速度，结果相同。MD5 汇编（USE_MD5_ASM）在启用 OpenSSL 时上游默认关闭，MD5 走 OpenSSL。
# ACL 用 fd + /proc/self/fd 方式设置（SUPPORT_ACL_FD）。musl 1.2.5 没有 Linux 6.13 新增的 SYS_*xattrat 编号，
#   configure 不启用 HAVE_XATTRAT_SYSCALLS；也不手工补编号：rsync 只在 ENOSYS 时回退，旧版 Docker/容器
#   seccomp 对未知 syscall 返回 EPERM，会被当成“可用”导致 ACL 设置全部失败。
RUN CPPFLAGS=-I/usr/local/include LDFLAGS="-static -L/usr/local/lib" LIBS=-lunistring \
        ./configure --with-openssl-conf=/dev/null --disable-md2man \
    && ! grep -q '^#define HAVE_XATTRAT_SYSCALLS' config.h \
    && for macro in SUPPORT_ACLS SUPPORT_ACL_FD SUPPORT_XATTRS HAVE_LINUX_XATTRS \
            SUPPORT_XXHASH SUPPORT_ZSTD SUPPORT_LZ4 USE_OPENSSL SUPPORT_IDN USE_ICONV_OPEN INET6; do \
        grep -q "^#define ${macro} 1" config.h || { echo "missing ${macro}" >&2; exit 1; }; \
    done \
    && grep -q '^#define ICONV_OPTION NULL' config.h \
    && grep -q '^#define NOBODY_GROUP "nobody"' config.h \
    && ! grep -q '^#define HAVE_LIBACL_AT' config.h \
    && make -j"${JOBS}" \
    && make check-progs \
    && nm rsync | grep -q ' T libiconv_open$'

# 上游测试按上游 CI 跑四遍：默认、协议 30、协议 29、真实 TCP 守护进程。排除两项不适用于本构建的测试：
# - fake-super-backup-fifo-regression：靠 LD_PRELOAD 注入故障，静态二进制不加载预载库。
# - misc-coverage：其中 --info=stats3 要求输出 malloc 统计，依赖 glibc 的 mallinfo，musl 没有。
# --network=none：测试只用回环地址，不访问外网。构建机的 DNS 若对任意域名返回地址（fake-IP 一类），
#   daemon-deny-dns-failopen 用来模拟解析失败的 .invalid 域名会被解析成功，测试失去意义；断网后解析必然失败。
# daemon-auth-group 假设 root 不是 daemon 组的附加成员（Debian 布局）；Alpine 的 /etc/group 把 root
#   列为 daemon 组成员，root 先命中读写规则，rsync 行为本身正确。仅在构建容器内去掉该成员关系，让测试按原意执行。
RUN --network=none sed -i 's/^daemon:x:2:root,/daemon:x:2:/' /etc/group \
    && ! id -Gn root | grep -qw daemon \
    && exclude=fake-super-backup-fifo-regression,misc-coverage \
    && ./runtests.py --rsync-bin="$PWD/rsync" -j "${JOBS}" --exclude="$exclude" \
    && ./runtests.py --rsync-bin="$PWD/rsync" -j "${JOBS}" --exclude="$exclude" --protocol=30 \
    && ./runtests.py --rsync-bin="$PWD/rsync" -j "${JOBS}" --exclude="$exclude" --protocol=29 \
    && ./runtests.py --rsync-bin="$PWD/rsync" -j "${JOBS}" --exclude="$exclude" --use-tcp --daemon-tests-only
RUN mkdir -p /out \
    && cp rsync /out/rsync \
    && cp rsync.1 rsyncd.conf.5 /out/ \
    && cp COPYING /out/COPYING \
    && strip /out/rsync

RUN file /out/rsync \
    && readelf -h /out/rsync > /tmp/elf-header \
    && case "${TARGETARCH}" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
        *) false ;; \
    esac \
    && readelf -l /out/rsync > /tmp/elf-program \
    && ! grep -q INTERP /tmp/elf-program \
    && readelf -d /out/rsync > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/rsync --version | tee /tmp/version \
    && grep -F "rsync  version ${RSYNC_VERSION}  protocol version 33" /tmp/version

# 只含产物、未经 smoke 测试，供调试：./build.sh 不使用这个阶段。
FROM scratch AS bin
COPY --from=builder /out/ /

FROM builder AS test
COPY test/smoke-test.py /build/smoke-test.py
RUN --network=none python3 /build/smoke-test.py /out

FROM scratch AS artifact
COPY --from=test /out/ /
