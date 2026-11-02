# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS build

ARG WIRESHARK_VERSION=4.6.7
ARG WIRESHARK_SHA512=a776d17815dcf74a7bf9b6e0e516ea20e37a2092515afa68fbae30e22b24793ffa4cd8f9bffa781d0b64683e8c2be84b7d0ec1bcb3ff25d62daf1afe652cbb3f
ARG LUA_VERSION=5.4.7
ARG LUA_SHA256=9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30

RUN apk add --no-cache \
        build-base \
        ca-certificates \
        cmake \
        curl \
        c-ares-dev \
        flex \
        bison \
        glib-dev \
        glib-static \
        libgcrypt-dev \
        libgcrypt-static \
        libgpg-error-static \
        libpcap-dev \
        libffi-dev \
        libxml2-dev \
        libxml2-static \
        xz-static \
        ninja \
        pcre2-dev \
        pcre2-static \
        python3 \
        zlib-dev \
        zlib-static \
    && curl --fail --location --retry 4 \
        --output /tmp/lua.tar.gz \
        "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${LUA_SHA256}" /tmp/lua.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/lua.tar.gz -C /tmp \
    && make -C "/tmp/lua-${LUA_VERSION}" linux MYCFLAGS=-fPIC \
    && make -C "/tmp/lua-${LUA_VERSION}" install INSTALL_TOP=/opt/static \
    && curl --fail --location --retry 4 \
        --output /tmp/wireshark.tar.xz \
        "https://www.wireshark.org/download/src/all-versions/wireshark-${WIRESHARK_VERSION}.tar.xz" \
    && printf '%s  %s\n' "${WIRESHARK_SHA512}" /tmp/wireshark.tar.xz | sha512sum -c - \
    && mkdir /src \
    && tar -xJf /tmp/wireshark.tar.xz --strip-components=1 -C /src \
    && grep -q 'bool run_anyway = false;' /src/epan/wslua/init_wslua.c \
    && sed -i 's/bool run_anyway = false;/bool run_anyway = true;/' /src/epan/wslua/init_wslua.c

WORKDIR /src

RUN cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=/opt/static \
        -DCMAKE_EXE_LINKER_FLAGS=-static \
        -DCMAKE_C_STANDARD_LIBRARIES=-llzma \
        -DBUILD_SHARED_LIBS=OFF \
        -DUSE_STATIC=ON \
        -DBUILD_wireshark=OFF \
        -DBUILD_stratoshark=OFF \
        -DBUILD_tshark=ON \
        -DBUILD_tfshark=OFF \
        -DBUILD_rawshark=OFF \
        -DBUILD_dumpcap=ON \
        -DBUILD_text2pcap=OFF \
        -DBUILD_mergecap=OFF \
        -DBUILD_reordercap=OFF \
        -DBUILD_editcap=OFF \
        -DBUILD_capinfos=OFF \
        -DBUILD_captype=OFF \
        -DBUILD_randpkt=OFF \
        -DBUILD_dftest=OFF \
        -DBUILD_dcerpcidl2wrs=OFF \
        -DBUILD_androiddump=OFF \
        -DBUILD_sshdump=OFF \
        -DBUILD_ciscodump=OFF \
        -DBUILD_dpauxmon=OFF \
        -DBUILD_randpktdump=OFF \
        -DBUILD_wifidump=OFF \
        -DBUILD_sdjournal=OFF \
        -DBUILD_udpdump=OFF \
        -DBUILD_sharkd=OFF \
        -DBUILD_mmdbresolve=OFF \
        -DENABLE_PLUGINS=OFF \
        -DENABLE_LUA=ON \
        -DENABLE_PCAP=ON \
        -DENABLE_ZLIB=ON \
        -DENABLE_ZLIBNG=OFF \
        -DENABLE_XXHASH=OFF \
        -DENABLE_MINIZIP=OFF \
        -DENABLE_MINIZIPNG=OFF \
        -DENABLE_LZ4=OFF \
        -DENABLE_BROTLI=OFF \
        -DENABLE_SNAPPY=OFF \
        -DENABLE_ZSTD=OFF \
        -DENABLE_NGHTTP2=OFF \
        -DENABLE_NGHTTP3=OFF \
        -DENABLE_SMI=OFF \
        -DENABLE_GNUTLS=OFF \
        -DENABLE_PKCS11=OFF \
        -DENABLE_CAP=OFF \
        -DENABLE_NETLINK=OFF \
        -DENABLE_KERBEROS=OFF \
        -DENABLE_SBC=OFF \
        -DENABLE_SPANDSP=OFF \
        -DENABLE_BCG729=OFF \
        -DENABLE_AMRNB=OFF \
        -DENABLE_AMRWB=OFF \
        -DENABLE_ILBC=OFF \
        -DENABLE_OPUS=OFF \
        -DENABLE_SINSP=OFF \
        -DENABLE_CPUINFO=OFF \
        -DENABLE_LTO=ON \
        -DENABLE_WERROR=OFF \
    && cmake --build build --target tshark dumpcap --parallel \
    && strip build/run/tshark build/run/dumpcap \
    && mkdir /out \
    && cp build/run/tshark build/run/dumpcap /out/

RUN /out/tshark --version \
    && /out/tshark --version | grep -q '+Lua 5.4' \
    && /out/dumpcap --version \
    && ! ldd /out/tshark 2>&1 | grep -q '=>' \
    && ! ldd /out/dumpcap 2>&1 | grep -q '=>'

FROM scratch AS artifact
COPY --from=build /out/ /
