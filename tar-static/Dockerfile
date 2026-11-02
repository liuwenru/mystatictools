ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG TAR_VERSION=1.35
ARG TAR_SHA256=4d62ff37342ec7aed748535323930c7cf94acf71c3591882b26a7ea50f3edc16
ARG LIBARCHIVE_VERSION=3.8.11
ARG LIBARCHIVE_SHA256=a3dc0872b1b39da34dc18ef1b944f0f11ffd37425d70ae04be679279f1cf43d2
ARG TARGETARCH
ARG JOBS=4

# 静态库来自 Alpine；gzip/bzip2/xz/zstd/lzip/lzop/acl/attr/e2fsprogs/cpio/zip 只用于测试，不进运行包。
RUN apk add --no-cache build-base linux-headers curl file python3 \
        acl-dev acl-static attr-dev libselinux-dev libselinux-static pcre2-static \
        gettext-dev gettext-static \
        zlib-dev zlib-static bzip2-dev bzip2-static xz-dev xz-static zstd-dev zstd-static \
        lz4-dev lz4-static lzo-dev openssl-dev openssl-libs-static libxml2-dev libxml2-static \
        gzip bzip2 xz zstd lzip lzop acl attr e2fsprogs cpio zip

WORKDIR /build/tar
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/tar.tar.xz \
        "https://ftp.gnu.org/gnu/tar/tar-${TAR_VERSION}.tar.xz" \
    && printf '%s  %s\n' "${TAR_SHA256}" /tmp/tar.tar.xz | sha256sum -c - \
    && tar -xJf /tmp/tar.tar.xz --strip-components=1
# NLS 启用，翻译目录与发行版一致；tar 1.35 的 Makefile 漏了 $(LIBINTL)，glibc 上不影响，
# 静态链接 GNU libintl 时缺符号，用 LIBS 补在链接命令末尾。
# RSH：不设置时 host:file 远程归档直接报错；与 Fedora/RHEL 一致用 ssh。
# --with-rmt：远端执行的 rmt 路径，Debian/RHEL 均为 /usr/sbin/rmt；本包不提供 rmt。
# FORCE_UNSAFE_CONFIGURE：容器内以 root 构建。
# 上游测试只跳过 xattr03：它只检查 uid 0，但写 trusted.* 需要 CAP_SYS_ADMIN，docker build 没有该能力；
# trusted.* 在宿主 root 下另行验证，见 test/VALIDATION.md。
RUN FORCE_UNSAFE_CONFIGURE=1 LDFLAGS=-static LIBS=-lintl RSH=/usr/bin/ssh \
        ./configure --localedir=/usr/share/locale --with-rmt=/usr/sbin/rmt \
    && grep -q '^#define ENABLE_NLS 1' config.h \
    && grep -q '^#define HAVE_POSIX_ACLS' config.h \
    && grep -q '^#define HAVE_XATTRS' config.h \
    && grep -q '^#define HAVE_SELINUX_SELINUX_H 1' config.h \
    && grep -q '^#define REMOTE_SHELL "/usr/bin/ssh"' config.h \
    && grep -q '^#define DEFAULT_RMT_COMMAND "/usr/sbin/rmt"' config.h \
    && make -j"${JOBS}" \
    && make -j"${JOBS}" check TESTSUITEFLAGS='-k !xattr03' \
    || { cat tests/testsuite.log 2>/dev/null | tail -200; exit 1; }
RUN mkdir -p /out \
    && cp src/tar /out/tar \
    && cp doc/tar.1 /out/tar.1 \
    && cp COPYING /out/COPYING.tar \
    && strip /out/tar \
    && make -C po install

WORKDIR /build/libarchive
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/libarchive.tar.xz \
        "https://github.com/libarchive/libarchive/releases/download/v${LIBARCHIVE_VERSION}/libarchive-${LIBARCHIVE_VERSION}.tar.xz" \
    && printf '%s  %s\n' "${LIBARCHIVE_SHA256}" /tmp/libarchive.tar.xz | sha256sum -c - \
    && tar -xJf /tmp/libarchive.tar.xz --strip-components=1
# 压缩、ACL、加密库全部静态链入，不调用外部压缩程序。--enable-bsdtar=static 只静态链接 libarchive，
# 其余库仍为动态；libtool 下需在 make 时用 -all-static 才是完全静态。
# libb2 在 Alpine 没有静态库，用 libarchive 自带的 BLAKE2s（仅 RAR5 校验用）。
# xar 用 libxml2；加密/摘要用 OpenSSL，不同时启用 nettle/mbedtls。
RUN ./configure --disable-shared --enable-static \
        --enable-bsdtar=static --enable-bsdunzip=static --disable-bsdcpio --disable-bsdcat \
        --with-openssl --with-xml2 --without-expat --with-lzo2 --without-libb2 \
        --without-nettle --without-mbedtls \
    && for macro in HAVE_LIBACL ARCHIVE_XATTR_LINUX HAVE_WORKING_FS_IOC_GETFLAGS HAVE_ICONV \
            HAVE_LIBXML2 HAVE_OPENSSL_EVP_H HAVE_LIBLZ4 HAVE_ZSTD_H HAVE_LZO_LZO1X_H \
            HAVE_LIBLZMA HAVE_LIBBZ2 HAVE_LIBZ; do \
        grep -q "^#define ${macro} 1" config.h || { echo "missing ${macro}" >&2; exit 1; }; \
    done \
    && make -j"${JOBS}" LDFLAGS=-all-static \
    && make -j"${JOBS}" check LDFLAGS=-all-static || { cat test-suite.log 2>/dev/null | tail -200; exit 1; }
# 上游测试在 /tmp 留下超长路径目录，buildkit 导出时会因 file name too long 失败，单独清理。
# busybox rm 处理不了超长路径，用 Python 基于目录 fd 的 rmtree。
RUN python3 -c 'import glob, shutil; [shutil.rmtree(p) for p in glob.glob("/tmp/*_test.*")]' \
    && ! ls -d /tmp/*_test.* 2>/dev/null
RUN cp bsdtar bsdunzip /out/ \
    && cp tar/bsdtar.1 unzip/bsdunzip.1 /out/ \
    && cp COPYING /out/COPYING.libarchive \
    && strip /out/bsdtar /out/bsdunzip

RUN for bin in tar bsdtar bsdunzip; do \
        file /out/$bin \
        && readelf -h /out/$bin > /tmp/elf-header \
        && case "${TARGETARCH}" in \
            amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
            arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
            *) false ;; \
        esac \
        && readelf -l /out/$bin > /tmp/elf-program \
        && ! grep -q INTERP /tmp/elf-program \
        && readelf -d /out/$bin > /tmp/elf-dynamic \
        && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
        || exit 1; \
    done \
    && /out/tar --version | tee /tmp/version \
    && grep -F "tar (GNU tar) ${TAR_VERSION}" /tmp/version \
    && /out/bsdtar --version | tee /tmp/version \
    && grep -F "bsdtar ${LIBARCHIVE_VERSION} - libarchive ${LIBARCHIVE_VERSION}" /tmp/version \
    && /out/bsdunzip --version | tee /tmp/version \
    && grep -F "bsdunzip ${LIBARCHIVE_VERSION} - libarchive ${LIBARCHIVE_VERSION}" /tmp/version

COPY test/smoke-test.py /build/smoke-test.py
RUN python3 /build/smoke-test.py /out

FROM scratch AS artifact
COPY --from=builder /out/ /
