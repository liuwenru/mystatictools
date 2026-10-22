# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS libraries

ARG NCURSES_VERSION=6.5
ARG NCURSES_SHA256=136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6
ARG FALLBACK_TERMS=ansi,linux,vt100,vt102,vt220,xterm,xterm-256color,xterm-direct,screen,screen-256color,tmux,tmux-256color,rxvt,rxvt-256color,alacritty,alacritty-direct,foot,foot-direct,xterm-kitty

RUN apk add --no-cache \
        build-base bison curl file gawk perl python3 texinfo \
        ncurses gettext-dev gettext-static gdbm-dev \
        libcap-dev libcap-static pcre2-dev pcre2-static

# 系统 terminfo 仍优先；离线无数据库时使用真正的内嵌终端定义。
WORKDIR /build/ncurses
RUN curl --fail --location --retry 4 \
        --output /tmp/ncurses.tar.gz \
        "https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${NCURSES_SHA256}" /tmp/ncurses.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/ncurses.tar.gz --strip-components=1 \
    && grep -q '^kitty|' misc/terminfo.src \
    && sed -i 's/^kitty|/kitty|xterm-kitty|/' misc/terminfo.src \
    && ./configure \
        --prefix=/opt/static \
        --enable-widec \
        --with-normal --without-shared --without-debug \
        --without-ada --without-cxx --without-cxx-binding \
        --without-progs --without-tests \
        --with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo \
        --with-tic-path=/usr/bin/tic \
        --with-infocmp-path=/usr/bin/infocmp \
        --with-fallbacks="${FALLBACK_TERMS}" \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make install

FROM libraries AS bash-builder
ARG BASH_VERSION=5.3
ARG BASH_SHA256=0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba
WORKDIR /build/bash
COPY bash-patches.sha256 /build/bash-patches.sha256
RUN curl --fail --location --retry 4 \
        --output /tmp/bash.tar.gz \
        "https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${BASH_SHA256}" /tmp/bash.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/bash.tar.gz --strip-components=1 \
    && mkdir /build/bash-patches \
    && cd /build/bash-patches \
    && while read -r checksum patchfile; do \
        curl --fail --location --retry 4 --output "$patchfile" \
            "https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}-patches/${patchfile}"; \
        printf '%s  %s\n' "$checksum" "$patchfile" | sha256sum -c - || exit 1; \
        patch --batch --forward -d /build/bash -p0 < "$patchfile" || exit 1; \
       done < /build/bash-patches.sha256 \
    && cd /build/bash \
    && CPPFLAGS="-I/opt/static/include -I/opt/static/include/ncursesw" \
       CFLAGS="-O2" LDFLAGS="-static -L/opt/static/lib" \
       ./configure --prefix=/usr/local \
        --enable-static-link --with-curses --without-bash-malloc \
        --enable-readline --enable-progcomp --enable-multibyte \
        --enable-net-redirections --enable-job-control --enable-nls \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make DESTDIR=/build/bash-install install \
    && mkdir -p /out/share/licenses/bash /out/share/locale \
    && cp bash /out/bash \
    && strip /out/bash \
    && cp COPYING /out/share/licenses/bash/ \
    && cp -a /build/bash-install/usr/local/share/locale/. /out/share/locale/ \
    && cp config.h /out/bash-config.h

FROM libraries AS zsh-builder
ARG ZSH_VERSION=5.9.2
ARG ZSH_SHA256=36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81
WORKDIR /build/zsh
RUN curl --fail --location --retry 4 \
        --output /tmp/zsh.tar.xz \
        "https://www.zsh.org/pub/zsh-${ZSH_VERSION}.tar.xz" \
    && printf '%s  %s\n' "${ZSH_SHA256}" /tmp/zsh.tar.xz | sha256sum -c - \
    && tar -xJf /tmp/zsh.tar.xz --strip-components=1 \
    && CPPFLAGS="-I/opt/static/include -I/opt/static/include/ncursesw" \
       CFLAGS="-O2" LDFLAGS="-static -L/opt/static/lib" \
       ./configure --prefix=/usr/local \
        --disable-dynamic --enable-multibyte --enable-maildir-support \
        --enable-pcre --enable-cap --enable-gdbm \
        --with-term-lib=ncursesw \
    && sed -i '/^name=zsh\/main /!s/ link=[^ ]*/ link=static/; s/ auto=yes/ auto=no/' config.modules \
    && make -C Src prep \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make DESTDIR=/build/zsh-install install.fns \
    && mkdir -p /out/share/zsh /out/share/licenses/zsh \
    && cp Src/zsh /out/zsh \
    && strip /out/zsh \
    && cp -a "/build/zsh-install/usr/local/share/zsh/${ZSH_VERSION}/functions" /out/share/zsh/ \
    && cp LICENCE /out/share/licenses/zsh/ \
    && cp config.h /out/zsh-config.h \
    && cp config.modules /out/zsh-config.modules

FROM libraries AS verify
ARG TARGETARCH
ARG BASH_VERSION=5.3
ARG ZSH_VERSION=5.9.2
COPY --from=bash-builder /out/ /out/
COPY --from=zsh-builder /out/ /out/
COPY init.zsh /out/init.zsh
COPY smoke-test.py /build/smoke-test.py
RUN set -eu; \
    case "$TARGETARCH" in amd64) machine='Advanced Micro Devices X86-64';; arm64) machine='AArch64';; *) exit 1;; esac; \
    for shell in bash zsh; do \
        file "/out/$shell"; \
        readelf -h "/out/$shell" | grep -F "$machine"; \
        ! readelf -l "/out/$shell" | grep -q INTERP; \
        ! readelf -d "/out/$shell" | grep -q '(NEEDED)'; \
    done; \
    /out/bash --version | head -1 | grep -F "version ${BASH_VERSION}.20("; \
    test "$(/out/zsh -fc 'print -r -- $ZSH_VERSION')" = "$ZSH_VERSION"; \
    apk info -v > /out/build-packages.txt; \
    rm -rf /etc/terminfo /lib/terminfo /usr/share/terminfo /opt/static/share/terminfo; \
    python3 /build/smoke-test.py /out > /out/test-results.txt; \
    cat /out/test-results.txt; \
    cd /out; \
    sha256sum bash zsh > SHA256SUMS

FROM scratch AS artifact
COPY --from=verify /out/ /
