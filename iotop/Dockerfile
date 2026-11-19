# syntax=docker/dockerfile:1
ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder

ARG IOTOP_VERSION=1.33
ARG IOTOP_SHA256=7c697a447f7ee95ccbf71619478a024f43016f8448e8eb4ce683e2baff124d9d
ARG NCURSES_VERSION=6.6
ARG NCURSES_SHA256=355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11
ARG TARGETARCH
ARG JOBS=4
ARG FALLBACK_TERMS=ansi,linux,vt100,vt102,vt220,xterm,xterm-256color,xterm-direct,screen,screen-256color,tmux,tmux-256color,rxvt,rxvt-256color,alacritty,foot,xterm-kitty

RUN apk add --no-cache build-base curl linux-headers ncurses pkgconf

# Rebuild the wide archive to embed fallback terminfo while keeping database lookup.
WORKDIR /build/ncurses
RUN set -eu; \
    curl -fsSL --retry 4 --retry-all-errors -o /tmp/ncurses.tar.gz \
      "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"; \
    printf '%s  %s\n' "$NCURSES_SHA256" /tmp/ncurses.tar.gz | sha256sum -c -; \
    tar -xzf /tmp/ncurses.tar.gz --strip-components=1; \
    if ! grep -q '^kitty|xterm-kitty|' misc/terminfo.src; then \
      grep -q '^kitty|' misc/terminfo.src; \
      sed -i 's/^kitty|/kitty|xterm-kitty|/' misc/terminfo.src; \
    fi; \
    ./configure --prefix=/opt/static --enable-widec --enable-pc-files \
      --with-pkg-config-libdir=/opt/static/lib/pkgconfig --with-normal \
      --without-shared --without-debug --without-ada --without-cxx \
      --without-cxx-binding --without-progs --without-tests --disable-setuid-environ \
      --with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo \
      --with-tic-path=/usr/bin/tic --with-infocmp-path=/usr/bin/infocmp \
      --with-fallbacks="$FALLBACK_TERMS"; \
    make -j"$JOBS"; \
    make install

WORKDIR /build/iotop
RUN set -eu; \
    curl -fsSL --retry 4 --retry-all-errors -o /tmp/iotop.tar.xz \
      "https://github.com/Tomas-M/iotop/releases/download/v${IOTOP_VERSION}/iotop-${IOTOP_VERSION}.tar.xz"; \
    printf '%s  %s\n' "$IOTOP_SHA256" /tmp/iotop.tar.xz | sha256sum -c -; \
    tar -xJf /tmp/iotop.tar.xz --strip-components=1; \
    export PKG_CONFIG_LIBDIR=/opt/static/lib/pkgconfig; \
    make -j"$JOBS" HAVELPIE=no LDFLAGS=-static \
      NCCC="$(pkg-config --cflags ncursesw)" NCLD="$(pkg-config --static --libs ncursesw)"; \
    mkdir -p /out; \
    install -s -m 0755 iotop /out/iotop; \
    cp iotop.8 COPYING LICENSE /out/; \
    cp /build/ncurses/COPYING /out/ncurses.COPYING; \
    printf '%s\n' "$IOTOP_VERSION" > /out/VERSION; \
    readelf -h /out/iotop > /tmp/elf-header; \
    case "$TARGETARCH" in \
      amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
      arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
      *) exit 1 ;; \
    esac; \
    readelf -l /out/iotop > /tmp/elf-program; \
    readelf -d /out/iotop > /tmp/elf-dynamic; \
    if grep -q INTERP /tmp/elf-program || grep -q '(NEEDED)' /tmp/elf-dynamic; then exit 1; fi; \
    test "$(/out/iotop --version)" = "/out/iotop $IOTOP_VERSION"

COPY test/terminfo.c /build/terminfo.c
# TASKSTATS access is tested separately on Linux hosts with sufficient privileges.
RUN --network=none set -eu; \
    export PKG_CONFIG_LIBDIR=/opt/static/lib/pkgconfig; \
    cc -static $(pkg-config --cflags ncursesw) /build/terminfo.c \
      -o /tmp/check-terminfo $(pkg-config --static --libs ncursesw); \
    mkdir -p /tmp/empty; \
    rm -rf /etc/terminfo /lib/terminfo /usr/share/terminfo /opt/static/share/terminfo; \
    export HOME=/tmp/empty TERMINFO=/tmp/empty TERMINFO_DIRS=/tmp/empty; \
    for term in $(printf '%s' "$FALLBACK_TERMS" | tr , ' '); do /tmp/check-terminfo "$term"; done; \
    XDG_CONFIG_HOME=/tmp/empty make check; \
    cd /out; \
    sha256sum iotop iotop.8 COPYING LICENSE ncurses.COPYING VERSION > SHA256SUMS

FROM scratch AS smoke
COPY --from=builder /out/iotop /iotop
RUN --network=none ["/iotop", "--version"]

FROM scratch AS artifact
COPY --from=builder /out/ /
COPY --from=smoke /iotop /iotop
