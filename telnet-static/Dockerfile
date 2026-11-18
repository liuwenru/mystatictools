ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG INETUTILS_VERSION=2.8
ARG INETUTILS_SHA256=57b3cf4f77555992881e5ba2a09a63b05aa2c56342a60ed4305b5f45938390b5
ARG SHISHI_VERSION=1.0.3
ARG SHISHI_SHA256=95798ffd12dd01a4f88e0311ee03ca4a26e5cb4e5e9059a40e4fc4d9f2917e92
ARG LIBTASN1_VERSION=4.21.0
ARG LIBTASN1_SHA256=1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87
ARG NCURSES_VERSION=6.6
ARG NCURSES_SHA256=355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11
ARG TARGETARCH
ARG JOBS=4
ARG FALLBACK_TERMS=ansi,dumb,linux,vt100,vt102,vt220,xterm,xterm-256color,xterm-direct,screen,screen-256color,tmux,tmux-256color,rxvt,rxvt-256color,alacritty,alacritty-direct,foot,foot-direct,xterm-kitty,xterm-ghostty
RUN apk add --no-cache build-base curl file patch python3 pkgconf ncurses \
        libidn-dev libgcrypt-dev libgcrypt-static libgpg-error-static

WORKDIR /build/ncurses
RUN curl -fL --retry 4 --retry-all-errors -o /tmp/ncurses.tar.gz \
        "https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" \
    && echo "${NCURSES_SHA256}  /tmp/ncurses.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/ncurses.tar.gz --strip-components=1 \
    && grep -q '^kitty|' misc/terminfo.src && grep -q '^ghostty|' misc/terminfo.src \
    && sed -i -e 's/^kitty|/kitty|xterm-kitty|/' -e 's/^ghostty|/ghostty|xterm-ghostty|/' misc/terminfo.src \
    && cf_cv_multiuser=yes ./configure --prefix=/opt/static --disable-widec \
        --with-normal --without-shared --without-debug --without-ada \
        --without-cxx --without-cxx-binding --without-progs --without-tests \
        --without-manpages --disable-db-install \
        --with-terminfo-dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo \
        --with-tic-path=/usr/bin/tic --with-infocmp-path=/usr/bin/infocmp \
        --with-fallbacks="${FALLBACK_TERMS}" \
    && make -j"${JOBS}" && make install

WORKDIR /build/libtasn1
RUN curl -fL --retry 4 --retry-all-errors -o /tmp/libtasn1.tar.gz \
        "https://ftp.gnu.org/gnu/libtasn1/libtasn1-${LIBTASN1_VERSION}.tar.gz" \
    && echo "${LIBTASN1_SHA256}  /tmp/libtasn1.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/libtasn1.tar.gz --strip-components=1 \
    && ./configure --prefix=/opt/static --disable-shared --enable-static \
    && make -j"${JOBS}" && make check && make install

WORKDIR /build/shishi
# STARTTLS 是 Shishi 到 KDC 的非标准扩展，不是 telnet 流加密；见 README。
RUN curl -fL --retry 4 --retry-all-errors -o /tmp/shishi.tar.gz \
        "https://ftp.gnu.org/gnu/shishi/shishi-${SHISHI_VERSION}.tar.gz" \
    && echo "${SHISHI_SHA256}  /tmp/shishi.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/shishi.tar.gz --strip-components=1 \
    && CPPFLAGS=-I/opt/static/include LDFLAGS='-L/opt/static/lib -static' \
       LIBS='-lgcrypt -lgpg-error' ./configure --prefix=/opt/static \
        --sysconfdir=/etc --with-conf-dir=/etc/shishi --with-skel-dir=/etc/shishi \
        --disable-shared --enable-static --disable-starttls --disable-pam \
    && make -j"${JOBS}" && make check && make install

WORKDIR /build/inetutils
RUN curl -fL --retry 4 --retry-all-errors -o /tmp/inetutils.tar.gz \
        "https://ftp.gnu.org/gnu/inetutils/inetutils-${INETUTILS_VERSION}.tar.gz" \
    && echo "${INETUTILS_SHA256}  /tmp/inetutils.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/inetutils.tar.gz --strip-components=1
COPY patches/ /build/patches/
# m4 与生成的 configure 已同步修改，保留发行包时间关系，避免不必要的 autotools 再生成。
RUN patch -p1 < /build/patches/default-port.patch \
    && patch -p1 < /build/patches/ncurses-tgetent.patch \
    && patch -p1 < /build/patches/prompt-flush.patch \
    && touch -r aclocal.m4 am/libcurses.m4 \
    && CPPFLAGS='-I/opt/static/include -I/opt/static/include/ncurses' LDFLAGS='-L/opt/static/lib -static' \
       LIBS='-ltasn1 -lgcrypt -lgpg-error -lidn' \
       ./configure --prefix=/usr --disable-servers --disable-clients --enable-telnet \
        --enable-authentication --enable-encryption --with-shishi=/opt/static \
        --with-idn --with-ncurses-include-dir=/opt/static/include/ncurses \
    && for feature in AUTHENTICATION ENCRYPTION SHISHI HAVE_TGETENT HAVE_IDN IPV6; do \
        grep -q "^#define ${feature} 1" config.h || { echo "Missing: $feature"; exit 1; }; \
       done

RUN make -j"${JOBS}" \
    && mkdir -p /out \
    && cp telnet/telnet /out/telnet && strip /out/telnet \
    && cp man/telnet.1 /out/ && cp COPYING /out/COPYING.inetutils \
    && cp /build/ncurses/COPYING /out/COPYING.ncurses \
    && cp /build/shishi/COPYING /out/COPYING.shishi \
    && cp /build/libtasn1/COPYING /out/COPYING.libtasn1
COPY licenses/COPYING.* /out/

RUN readelf -h /out/telnet > /tmp/header \
    && case "$TARGETARCH" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/header ;; \
        *) exit 1 ;; esac \
    && readelf -l /out/telnet > /tmp/program \
    && ! grep -q INTERP /tmp/program \
    && readelf -d /out/telnet > /tmp/dynamic \
    && ! grep -q '(NEEDED)' /tmp/dynamic \
    && file /out/telnet \
    && /out/telnet --version | tee /tmp/version \
    && grep -qx "telnet (GNU inetutils) ${INETUTILS_VERSION}" /tmp/version \
    && { cat /tmp/version; uname -m; apk info -v; \
         echo "ncurses=${NCURSES_VERSION} shishi=${SHISHI_VERSION} libtasn1=${LIBTASN1_VERSION}"; \
         echo 'KDC_STARTTLS=no'; echo "fallbacks=${FALLBACK_TERMS}"; } > /out/BUILD-INFO
FROM builder AS verified
COPY test/ /build/test/
RUN python3 /build/test/smoke-test.py /out/telnet
COPY README.md /out/README.md
RUN cd /out && sha256sum telnet telnet.1 COPYING.* BUILD-INFO README.md > SHA256SUMS
FROM scratch AS artifact
COPY --from=verified /out/ /
