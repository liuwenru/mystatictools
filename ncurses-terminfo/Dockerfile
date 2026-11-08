ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG NCURSES_VERSION=6.6
ARG NCURSES_SHA256=355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11
ARG TARGETARCH
ARG JOBS=4

RUN apk add --no-cache build-base curl file

WORKDIR /build/ncurses
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/ncurses.tar.gz \
        "https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${NCURSES_SHA256}" /tmp/ncurses.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/ncurses.tar.gz --strip-components=1

# kitty、ghostty 实际设置的 TERM 是 xterm-kitty、xterm-ghostty，ncurses 条目只叫 kitty、ghostty。
# 两者内容来自终端上游，补上 TERM 实际使用的名字；与 tmux、pstree-static 的做法一致。
RUN grep -q '^kitty|' misc/terminfo.src \
    && grep -q '^ghostty|' misc/terminfo.src \
    && ! grep -qE '^(xterm-kitty|xterm-ghostty)[|,]|\|(xterm-kitty|xterm-ghostty)\|' misc/terminfo.src \
    && sed -i -e 's/^kitty|/kitty|xterm-kitty|/' -e 's/^ghostty|/ghostty|xterm-ghostty|/' misc/terminfo.src

# --disable-widec：窄字符构建不启用 ext-colors，tic 写出传统 terminfo 格式（magic 0432），
#   超过 32767 的数值截断为 32767。ncurses 6.1 之后的默认构建会对 pairs#0x10000 等条目写出
#   扩展数值格式（magic 01036），CentOS 7 等 ncurses 5 系统读不了。
# --enable-symlinks：别名用软链接。aarch64 产物导出到 SSHFS 共享目录，不依赖硬链接。
# cf_cv_multiuser=yes：构建容器里没有普通用户时，configure 会让 root 忽略 TERMINFO 等变量；
#   这里与发行版 ncurses 保持一致。
RUN cf_cv_multiuser=yes LDFLAGS=-static ./configure \
        --prefix=/usr \
        --disable-widec \
        --enable-symlinks \
        --with-normal \
        --without-shared \
        --without-debug \
        --without-ada \
        --without-cxx \
        --without-cxx-binding \
        --without-tests \
        --without-manpages \
        --disable-db-install \
        --with-default-terminfo-dir=/usr/share/terminfo \
        --with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo \
    && make -j"${JOBS}" \
    && grep -qE '^#if 0[[:space:]]+/\* NCURSES_EXT_COLORS' include/curses.h

ARG PKG=/out/ncurses-terminfo
RUN mkdir -p "${PKG}/bin" "${PKG}/share" \
    && for bin in tic infocmp toe tput clear tset; do cp "progs/${bin}" "${PKG}/bin/${bin}" || exit 1; done \
    && ln -s tset "${PKG}/bin/reset" \
    && ln -s tic "${PKG}/bin/captoinfo" \
    && ln -s tic "${PKG}/bin/infotocap" \
    && strip "${PKG}"/bin/tic "${PKG}"/bin/infocmp "${PKG}"/bin/toe "${PKG}"/bin/tput \
        "${PKG}"/bin/clear "${PKG}"/bin/tset \
    && cp misc/terminfo.src "${PKG}/share/terminfo.src" \
    && cp COPYING "${PKG}/COPYING.ncurses" \
    && "${PKG}/bin/tic" -x -s -o "${PKG}/share/terminfo" "${PKG}/share/terminfo.src"

COPY install.sh ${PKG}/install.sh

RUN for bin in tic infocmp toe tput clear tset; do \
        f="${PKG}/bin/${bin}"; \
        file "$f" \
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
        || exit 1; \
    done \
    && "${PKG}/bin/tic" -V | tee /tmp/version \
    && grep -F "ncurses ${NCURSES_VERSION}." /tmp/version

# 删除构建容器自带的 terminfo 数据库后测试，确认只靠包内文件即可使用。
COPY test/smoke-test.sh /build/smoke-test.sh
RUN rm -rf /etc/terminfo /lib/terminfo /usr/share/terminfo \
    && sh /build/smoke-test.sh "${PKG}"

RUN cd "${PKG}" \
    && find bin install.sh COPYING.ncurses share/terminfo.src -type f | sort | xargs sha256sum > SHA256SUMS

FROM scratch AS artifact
COPY --from=builder /out/ /
