ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG UNZIP_SHA256=036d96991646d0449ed0aa952e4fbe21b476ce994abc276e49d30e686708bd37
ARG UBUNTU_DEBIAN_VERSION=6.0-31ubuntu1
ARG UBUNTU_DEBIAN_SHA256=7a39f16123ec664073b997690bddd68f5e9d1c8cc36e8b2a249c3ba8b73b221c
ARG TARGETARCH
ARG JOBS=4

# zip/mandoc/bash 只用于测试，不进运行包。
RUN apk add --no-cache build-base curl file python3 bzip2-dev bzip2-static zip mandoc bash

WORKDIR /build/unzip
# 上游 Info-ZIP UnZip 6.0 原始包（与 Debian/Ubuntu orig.tar.gz 逐字节相同）+ Ubuntu 补丁集。
# Ubuntu 6.0-31ubuntu1 = Debian 6.0-31 全部补丁 + -O/-I 文件名字符集、代码页修正、CVE-2021-4217。
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/unzip60.tar.gz \
        "https://downloads.sourceforge.net/project/infozip/UnZip%206.x%20%28latest%29/UnZip%206.0/unzip60.tar.gz" \
    && printf '%s  %s\n' "${UNZIP_SHA256}" /tmp/unzip60.tar.gz | sha256sum -c - \
    && curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/unzip-debian.tar.xz \
        "https://archive.ubuntu.com/ubuntu/pool/main/u/unzip/unzip_${UBUNTU_DEBIAN_VERSION}.debian.tar.xz" \
    && printf '%s  %s\n' "${UBUNTU_DEBIAN_SHA256}" /tmp/unzip-debian.tar.xz | sha256sum -c - \
    && tar -xzf /tmp/unzip60.tar.gz --strip-components=1 \
    && tar -xJf /tmp/unzip-debian.tar.xz \
    && while read -r p; do \
        case "$p" in ""|\#*) continue ;; esac; \
        patch -p1 --forward < "debian/patches/$p" || exit 1; \
    done < debian/patches/series
# 本地补丁：musl iconv 没有 CP936 这个名字，改用其超集 GB18030；见 patches/ 内说明。
COPY patches/ /build/patches/
RUN for p in /build/patches/*.patch; do patch -p1 --forward < "$p" || exit 1; done

# 编译宏与 Debian debian/rules 相同；bzip2 静态链接。
RUN make -j"${JOBS}" -f unix/Makefile CC=gcc LF2=-static \
        D_USE_BZ2=-DUSE_BZIP2 L_BZ2=-lbz2 \
        CF="-O2 -Wall -I. -DACORN_FTYPE_NFS -DWILD_STOP_AT_DIR -DLARGE_FILE_SUPPORT \
            -DUNICODE_SUPPORT -DUNICODE_WCHAR -DUTF8_MAYBE_NATIVE -DNO_LCHMOD \
            -DDATE_FORMAT=DF_YMD -DUSE_BZIP2 -DIZ_HAVE_UXUIDGID -DNOMEMCPY \
            -DNO_WORKING_ISPRINT" \
        unzips \
    && make -f unix/Makefile check 2>&1 | tee /tmp/check.log \
    && grep -q '#####  testing complete' /tmp/check.log \
    && ! grep -q 'ERROR' /tmp/check.log

RUN mkdir -p /out \
    && cp unzip funzip /out/ \
    && ln -s unzip /out/zipinfo \
    && cp man/unzip.1 man/zipinfo.1 man/funzip.1 /out/ \
    && cp LICENSE /out/LICENSE.unzip \
    && strip /out/unzip /out/funzip

RUN for bin in unzip funzip; do \
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
    && /out/unzip -v | tee /tmp/version \
    && grep -F 'UnZip 6.00 of 20 April 2009, by Debian' /tmp/version \
    && grep -F 'USE_BZIP2' /tmp/version \
    && grep -F 'ZIP64_SUPPORT' /tmp/version \
    && grep -F 'UNICODE_SUPPORT' /tmp/version

# Ubuntu autopkgtest：装到 /usr/bin 后运行，umask 002 与 Ubuntu 测试环境一致。
# 排除 ManPage（依赖 man-db 的 man -P cat，Alpine 的 mandoc/man-db 均不可用）和 ZipGrep
# （shell 脚本，依赖系统 egrep/sed，不进运行包）用例；手册页在 smoke-test.py 中用 mandoc 检查。
COPY test/run-ubuntu-tests.py /build/run-ubuntu-tests.py
RUN make -f unix/Makefile install prefix=/usr \
    && mkdir /tmp/ubuntu-tests && cd /tmp/ubuntu-tests \
    && umask 002 \
    && python3 /build/run-ubuntu-tests.py /build/unzip/debian/tests/SmokeTests.py \
    && rm -rf /tmp/ubuntu-tests

COPY test/smoke-test.py /build/smoke-test.py
RUN python3 /build/smoke-test.py /out

FROM scratch AS artifact
COPY --from=builder /out/ /
