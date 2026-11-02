ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG PSMISC_VERSION=23.7
ARG PSMISC_SHA256=58c55d9c1402474065adae669511c191de374b0871eec781239ab400b907c327
ARG NCURSES_VERSION=6.6
ARG NCURSES_SHA256=355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11
ARG FALLBACK_TERMS=ansi,linux,vt100,vt102,vt220,xterm,xterm-256color,xterm-direct,screen,screen-256color,tmux,tmux-256color,rxvt,rxvt-256color,alacritty,alacritty-direct,foot,foot-direct,xterm-kitty
ARG PROCS_VERSION=0.14.12
ARG PROCS_SHA256_AMD64=81964faf9d5cd0e9f399d5d0954fb6fe4d4d9f7d3cbec4507633df5a45b11713
ARG PROCS_SHA256_ARM64=74b4f82acc6fe553cbd5af20ba0baac420b42bef9bb0cbb38fef14b8317d9f91
ARG PROCS_LICENSE_SHA256=feb87a2e0c305de3464cc44077da5393c52d8ca6362d37427157d04ec6f4510d
ARG TARGETARCH
ARG JOBS=4

# ncurses 包只提供构建时生成内嵌 terminfo 所需的 tic/infocmp。
# gettext-static 提供静态 GNU libintl；psmisc-lang 只用于测试翻译文件的查找路径。
RUN apk add --no-cache build-base linux-headers curl file ncurses python3 xz \
        gettext-dev gettext-static psmisc-lang

# pstree 的 -h/-H 高亮需要 terminfo。自建 ncurses 内嵌常见终端定义，
# 同时保留对目标机 terminfo 数据库的正常查询。pstree 只用 termcap 层接口，
# 所以构建窄字符的独立 libtinfo，与 psmisc configure 查找的 -ltinfo 对应。
# cf_cv_multiuser=yes：configure 在构建容器的 /etc/passwd 中找不到普通用户时，会让 root 忽略
# TERMINFO/TERMINFO_DIRS/~/.terminfo；这里与发行版 ncurses 保持一致。setuid 程序仍会忽略这些变量。
WORKDIR /build/ncurses
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/ncurses.tar.gz \
        "https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${NCURSES_SHA256}" /tmp/ncurses.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/ncurses.tar.gz --strip-components=1 \
    && grep -q '^kitty|' misc/terminfo.src \
    && sed -i 's/^kitty|/kitty|xterm-kitty|/' misc/terminfo.src \
    && cf_cv_multiuser=yes ./configure \
        --prefix=/opt/static \
        --with-termlib \
        --disable-widec \
        --disable-ext-colors \
        --with-normal \
        --without-shared \
        --without-debug \
        --without-ada \
        --without-cxx \
        --without-cxx-binding \
        --without-progs \
        --without-tests \
        --disable-db-install \
        --with-default-terminfo-dir=/usr/share/terminfo \
        --with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo \
        --with-tic-path=/usr/bin/tic \
        --with-infocmp-path=/usr/bin/infocmp \
        --with-fallbacks="${FALLBACK_TERMS}" \
    && make -j"${JOBS}" \
    && make install

WORKDIR /build/psmisc
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/psmisc.tar.xz \
        "https://downloads.sourceforge.net/project/psmisc/psmisc/psmisc-${PSMISC_VERSION}.tar.xz" \
    && printf '%s  %s\n' "${PSMISC_SHA256}" /tmp/psmisc.tar.xz | sha256sum -c - \
    && tar -xJf /tmp/psmisc.tar.xz --strip-components=1
# NLS 必须启用：pstree 只在 ENABLE_NLS 时调用 setlocale，否则无法按 locale 自动使用 UTF-8 线条。
# 翻译目录设为 /usr/share/locale，与发行版 psmisc 的 .mo 位置一致。不用 --prefix=/usr：
# 那样 gettext 宏会直接链接 /usr/lib/libintl.so，静态链接失败。
# SELinux/AppArmor 库在 pstree 中是 dlopen 加载，静态程序无法使用，
# 不启用时 -Z 改读 /proc/PID/attr/current。
RUN CPPFLAGS="-I/opt/static/include -I/opt/static/include/ncurses" \
       LDFLAGS="-static -L/opt/static/lib" \
       ./configure --localedir=/usr/share/locale \
    && grep -q '^TERMCAP_LIB = -ltinfo$' Makefile \
    && grep -q '^USE_NLS = yes$' Makefile \
    && grep -q '^LIBINTL = -lintl$' Makefile \
    && grep -q '^localedir = /usr/share/locale$' Makefile \
    && make -j"${JOBS}" src/pstree \
    && mkdir -p /out \
    && cp src/pstree /out/pstree \
    && cp doc/pstree.1 /out/pstree.1 \
    && cp COPYING /out/COPYING.psmisc \
    && strip /out/pstree

WORKDIR /build/procs
RUN case "${TARGETARCH}" in \
        amd64) procs_arch=x86_64; procs_sha256="${PROCS_SHA256_AMD64}" ;; \
        arm64) procs_arch=aarch64; procs_sha256="${PROCS_SHA256_ARM64}" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/procs.zip \
        "https://github.com/dalance/procs/releases/download/v${PROCS_VERSION}/procs-v${PROCS_VERSION}-${procs_arch}-linux.zip" \
    && printf '%s  %s\n' "${procs_sha256}" /tmp/procs.zip | sha256sum -c - \
    && curl --fail --location --retry 4 --retry-all-errors \
        --output /out/LICENSE.procs \
        "https://raw.githubusercontent.com/dalance/procs/v${PROCS_VERSION}/LICENSE" \
    && printf '%s  %s\n' "${PROCS_LICENSE_SHA256}" /out/LICENSE.procs | sha256sum -c - \
    && unzip -o /tmp/procs.zip procs -d /out \
    && chmod 0755 /out/procs

# 两个程序都检查架构、动态解释器和 NEEDED；procs 是官方发布的二进制，不重新编译。
RUN for bin in pstree procs; do \
        file /out/$bin \
        && readelf -h /out/$bin > /tmp/elf-header \
        && case "${TARGETARCH}" in \
            amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
            arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
        esac \
        && readelf -l /out/$bin > /tmp/elf-program \
        && ! grep -q INTERP /tmp/elf-program \
        && readelf -d /out/$bin > /tmp/elf-dynamic \
        && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
        || exit 1; \
    done \
    && /out/pstree -V 2>&1 | tee /tmp/version \
    && grep -F "pstree (PSmisc) ${PSMISC_VERSION}" /tmp/version \
    && /out/procs --version | tee /tmp/version \
    && grep -F "procs \"${PROCS_VERSION} " /tmp/version

# 删除构建容器中的 terminfo 数据库后测试，确认内嵌 fallback 可用。
COPY test/smoke-test.py /build/smoke-test.py
RUN rm -rf /etc/terminfo /lib/terminfo /usr/share/terminfo \
    && python3 /build/smoke-test.py /out

FROM scratch AS artifact
COPY --from=builder /out/ /
