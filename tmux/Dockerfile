# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder

ARG TMUX_VERSION=3.8
ARG TMUX_SHA256=e79c699c7e949dccd0a4a125e17b8d1261e311b16979dbc8eb34542f3966d82e
ARG NCURSES_VERSION=6.5
ARG NCURSES_SHA256=136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6
ARG FALLBACK_TERMS=ansi,linux,vt100,vt102,vt220,xterm,xterm-256color,xterm-direct,screen,screen-256color,tmux,tmux-256color,rxvt,rxvt-256color,alacritty,alacritty-direct,foot,foot-direct,xterm-kitty

RUN apk add --no-cache \
        build-base bison curl file libevent-dev libevent-static \
        ncurses pkgconf python3 utf8proc-dev

# Build our own wide-character ncurses to embed terminfo fallbacks. Keep normal
# database lookup too, so unusual terminals can still use the host's terminfo.
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
        --enable-pc-files \
        --with-pkg-config-libdir=/opt/static/lib/pkgconfig \
        --with-normal \
        --without-shared \
        --without-debug \
        --without-ada \
        --without-cxx \
        --without-cxx-binding \
        --without-progs \
        --without-tests \
        --with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo \
        --with-tic-path=/usr/bin/tic \
        --with-infocmp-path=/usr/bin/infocmp \
        --with-fallbacks="${FALLBACK_TERMS}" \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make install

WORKDIR /build/tmux
RUN curl --fail --location --retry 4 \
        --output /tmp/tmux.tar.gz \
        "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${TMUX_SHA256}" /tmp/tmux.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/tmux.tar.gz --strip-components=1 \
    && PKG_CONFIG_PATH=/opt/static/lib/pkgconfig \
       CFLAGS="-O2 -ffunction-sections -fdata-sections" \
       LDFLAGS="-static -Wl,--gc-sections" \
       ./configure \
        --enable-static \
        --enable-sixel \
        --enable-utf8proc \
        --disable-systemd \
        --disable-utempter \
        --with-TERM=screen-256color \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && strip tmux \
    && mkdir -p /out \
    && cp tmux /out/tmux \
    && file /out/tmux \
    && ! readelf -l /out/tmux | grep -q 'INTERP' \
    && ! readelf -d /out/tmux 2>&1 | grep -q '(NEEDED)' \
    && /out/tmux -V \
    && test "$(/out/tmux -V)" = "tmux ${TMUX_VERSION}"

# Test a real PTY with no on-disk terminfo. This stage must succeed before export.
COPY smoke-test.py /build/smoke-test.py
RUN rm -rf /etc/terminfo /lib/terminfo /usr/share/terminfo /opt/static/share/terminfo \
    && python3 /build/smoke-test.py /out/tmux

FROM scratch AS artifact
COPY --from=builder /out/tmux /tmux
