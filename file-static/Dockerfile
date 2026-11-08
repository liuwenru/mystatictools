ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG FILE_VERSION=5.48
ARG FILE_SHA256=ed14656883b23a364b4057c05595d93252da9bc473d30106519519d0da141283
ARG LZLIB_VERSION=1.16
ARG LZLIB_SHA256=203228de911780309dad6813e51541d7ea89469784f01cb661edba080ff1b038
ARG TARGETARCH
ARG JOBS=4

# 内置解压（-z）用到的 zlib、bzip2、xz、zstd 用 Alpine 静态库；lzlib 在 Alpine 只有动态库，从源码构建。
# build-base 依赖 Alpine 的 file/libmagic，冒烟测试前删除其 magic 数据库。
# 压缩工具只用于生成测试样例；lz4 用于测试 -z 调用外部解压命令。
RUN apk add --no-cache build-base curl \
        zlib-dev zlib-static bzip2-dev bzip2-static xz-dev xz-static zstd-dev zstd-static \
        bzip2 xz zstd lzip lz4 python3

WORKDIR /build/lzlib
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/lzlib.tar.gz \
        "https://download.savannah.nongnu.org/releases/lzip/lzlib/lzlib-${LZLIB_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${LZLIB_SHA256}" /tmp/lzlib.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/lzlib.tar.gz --strip-components=1 \
    && ./configure --prefix=/opt/static CFLAGS=-O2 \
    && make -j"${JOBS}" \
    && make install \
    && test -f /opt/static/lib/liblz.a

WORKDIR /build/file
COPY embed-magic.patch /build/embed-magic.patch
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/file.tar.gz \
        "https://astron.com/pub/file/file-${FILE_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${FILE_SHA256}" /tmp/file.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/file.tar.gz --strip-components=1 \
    && patch -p1 < /build/embed-magic.patch

# 压缩库显式 --enable：缺依赖时 configure 直接失败，不会悄悄关闭。
# lrzip：Alpine 的 lrzip 包不带 liblrzip，不启用；.lrz 仍可识别，-z 时调用外部 lrzip 命令。
# 不启用 seccomp、Landlock 沙箱（与 Fedora/Debian/Alpine 一致）：上游在 seccomp 沙箱下设置
#   MAGIC_NO_COMPRESS_FORK，-z 对所有格式报 "Fork is required to uncompress"，必须加 -S；
#   Landlock 禁止执行外部解压命令，且未编译 seccomp 时 -S 无法关闭它。见 README。
# 第一次 make 生成 src/file 和 magic/magic.mgc（magic.mgc 由刚编译的 file 生成）；
# 第二次只重编 file.c，用 .incbin 把 magic.mgc 内嵌进去，并用 -all-static 完全静态链接。
RUN CPPFLAGS=-I/opt/static/include LDFLAGS=-L/opt/static/lib ./configure \
        --prefix=/usr \
        --disable-shared \
        --enable-static \
        --enable-zlib \
        --enable-bzlib \
        --enable-xzlib \
        --enable-zstdlib \
        --enable-lzlib \
        --disable-lrziplib \
        --disable-libseccomp \
        --disable-landlock \
        --enable-fsect-man5 \
    && for d in HAVE_ZLIB_H ZLIBSUPPORT HAVE_BZLIB_H BZLIBSUPPORT HAVE_LZMA_H XZLIBSUPPORT \
            HAVE_ZSTD_H ZSTDLIBSUPPORT HAVE_LZLIB_H LZLIBSUPPORT; do \
        grep -q "^#define ${d} 1" config.h || { echo "缺少 ${d}" >&2; exit 1; }; \
    done \
    && ! grep -qE '^#define (HAVE_LIBSECCOMP|HAVE_LINUX_LANDLOCK_H) 1' config.h \
    && make -j"${JOBS}" \
    && test -s magic/magic.mgc \
    && rm -f src/file.o src/file \
    && make -C src file \
        CPPFLAGS="-I/opt/static/include -DFILE_EMBED_MAGIC='\"/build/file/magic/magic.mgc\"'" \
        LDFLAGS="-L/opt/static/lib -all-static" \
    && mkdir -p /out \
    && cp src/file /out/file \
    && strip /out/file \
    && cp doc/file.1 doc/magic.5 /out/ \
    && cp COPYING /out/COPYING.file \
    && cp /build/lzlib/COPYING /out/COPYING.lzlib

RUN f=/out/file \
    && readelf -h "$f" > /tmp/elf-header \
    && case "${TARGETARCH}" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && readelf -l "$f" > /tmp/elf-program \
    && ! grep -q INTERP /tmp/elf-program \
    && readelf -d "$f" > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/file --version | tee /tmp/version \
    && grep -qx "file-${FILE_VERSION}" /tmp/version \
    && grep -q 'magic file embedded' /tmp/version \
    && ! grep -qE 'seccomp|Landlock' /tmp/version \
    && /out/file /out/file

# 上游测试套件（tests/ 下的样例用 magic/magic.mgc 测试，不依赖内嵌数据）。
RUN make -C tests check

# 系统中没有任何 magic 数据库时，测试内嵌数据库、压缩、MIME 和覆盖方式。
COPY test/smoke-test.sh /build/smoke-test.sh
RUN rm -f /usr/share/misc/magic /usr/share/misc/magic.mgc \
    && ! ls /usr/share/misc/magic* /usr/share/file /usr/lib/file /etc/magic 2>/dev/null \
    && cp /build/file/magic/magic.mgc /tmp/ref-magic.mgc \
    && sh /build/smoke-test.sh /out/file /tmp/ref-magic.mgc

RUN cd /out && sha256sum file file.1 magic.5 COPYING.file COPYING.lzlib > SHA256SUMS

FROM scratch AS artifact
COPY --from=builder /out/ /
