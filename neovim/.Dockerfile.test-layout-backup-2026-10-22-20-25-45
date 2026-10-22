# syntax=docker/dockerfile:1
ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS extras
RUN apk add --no-cache build-base cmake ninja curl python3 xz file binutils
WORKDIR /build
COPY extras.json fetch-extras.py /build/
ARG TARGETARCH
RUN python3 /build/fetch-extras.py "${TARGETARCH}"
WORKDIR /build/jq
RUN ./configure --disable-docs --disable-maintainer-mode --disable-shared \
      --enable-static --with-oniguruma=builtin LDFLAGS=-static \
    && make -j4 LDFLAGS=-all-static \
    && cp jq /out/nvim/libexec/jq
WORKDIR /build/libxml2
RUN cmake -S . -B build -G Ninja -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_SHARED_LIBS=OFF -D CMAKE_EXE_LINKER_FLAGS=-static \
      -D LIBXML2_WITH_MODULES=OFF -D LIBXML2_WITH_TESTS=OFF \
    && cmake --build build --target xmllint --parallel 4 \
    && cp build/xmllint /out/nvim/libexec/xmllint
RUN for tool in /out/nvim/libexec/*; do \
      strip "$tool"; file "$tool"; \
      if readelf -l "$tool" | grep -q INTERP; then exit 1; fi; \
      if readelf -d "$tool" | grep -q '(NEEDED)'; then exit 1; fi; \
      case "${TARGETARCH}" in \
        amd64) readelf -h "$tool" | grep -q 'Advanced Micro Devices X86-64' ;; \
        arm64) readelf -h "$tool" | grep -q AArch64 ;; \
        *) exit 1 ;; \
      esac || exit 1; \
    done
FROM alpine:${ALPINE_VERSION} AS builder
ARG NVIM_VERSION=0.12.6
ARG NVIM_SHA256=8629fdc5eb951daf89a76f68cad12f2f1e03fab0d539150ba3fe6d177d254b7f
ARG BUILD_JOBS=4
RUN apk add --no-cache build-base cmake ninja coreutils curl gettext-tiny-dev \
    git linux-headers python3 file binutils tmux
WORKDIR /build/neovim
RUN curl -fL --retry 4 --retry-all-errors -o /build/neovim.tar.gz \
      "https://codeload.github.com/neovim/neovim/tar.gz/refs/tags/v${NVIM_VERSION}" \
    && echo "${NVIM_SHA256}  /build/neovim.tar.gz" | sha256sum -c - \
    && tar -xzf /build/neovim.tar.gz --strip-components=1
COPY fetch-deps.py /build/fetch-deps.py
RUN python3 /build/fetch-deps.py
COPY static-parsers.py /build/static-parsers.py
RUN python3 /build/static-parsers.py
RUN cmake -S cmake.deps -B .deps -G Ninja -D CMAKE_BUILD_TYPE=Release \
    && cmake --build .deps --parallel "${BUILD_JOBS}"
RUN cmake -S . -B build -G Ninja -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/opt/nvim -D STATIC_BUILD=ON \
    && cmake --build build --parallel "${BUILD_JOBS}" \
    && DESTDIR=/out cmake --install build \
    && mv /out/opt/nvim /out/nvim \
    && strip /out/nvim/bin/nvim \
    && cp LICENSE.txt /out/nvim/LICENSE.txt \
    && file /out/nvim/bin/nvim \
    && ! readelf -l /out/nvim/bin/nvim | grep -q INTERP \
    && ! readelf -d /out/nvim/bin/nvim | grep -q '(NEEDED)' \
    && /out/nvim/bin/nvim --version | tee /out/nvim/BUILD-VERSION.txt \
    && /out/nvim/bin/nvim --version | grep -F "NVIM v${NVIM_VERSION}"
COPY smoke-test.lua smoke-test.py nvim-tree-test.lua /build/
COPY init-offline.lua /out/nvim/examples/init.lua
COPY bundle-sources.py /build/bundle-sources.py
RUN python3 /build/bundle-sources.py
ARG NVIM_TREE_VERSION=nvim-tree-v1.19.0
ARG NVIM_TREE_SHA256=3728c6148ccccdcbb59ea5d00718d523cb5a817cc6a03fa532b1d171cbe0702e
RUN curl -fL --retry 4 --retry-all-errors \
      -o /out/sources/nvim-tree.tar.gz \
      "https://codeload.github.com/nvim-tree/nvim-tree.lua/tar.gz/refs/tags/${NVIM_TREE_VERSION}" \
    && echo "${NVIM_TREE_SHA256}  /out/sources/nvim-tree.tar.gz" | sha256sum -c - \
    && mkdir -p /out/nvim/share/nvim/runtime/pack/offline/opt/nvim-tree.lua \
    && tar -xzf /out/sources/nvim-tree.tar.gz --strip-components=1 \
         -C /out/nvim/share/nvim/runtime/pack/offline/opt/nvim-tree.lua \
    && mkdir -p /out/nvim/licenses/nvim-tree \
    && cp /out/nvim/share/nvim/runtime/pack/offline/opt/nvim-tree.lua/LICENSE /out/nvim/licenses/nvim-tree/ \
    && printf '%s\nSHA256 %s\n' "${NVIM_TREE_VERSION}" "${NVIM_TREE_SHA256}" > /out/nvim/NVIM-TREE-VERSION.txt \
    && /out/nvim/bin/nvim --headless -u NONE -i NONE \
         '+helptags /out/nvim/share/nvim/runtime/pack/offline/opt/nvim-tree.lua/doc' '+qa!'
COPY Dockerfile build.sh fetch-deps.py static-parsers.py bundle-sources.py smoke-test.lua smoke-test.py nvim-tree-test.lua init-offline.lua README.md /out/sources/build/
COPY --from=extras /out/nvim/ /out/nvim/
COPY --from=extras /out/sources/ /out/sources/
COPY extras.json fetch-extras.py enhancements-test.lua /out/sources/build/
COPY enhancements-test.lua /build/
RUN /out/nvim/bin/nvim --headless -u NONE -i NONE \
      '+packadd conform.nvim' '+packadd indent-blankline.nvim' '+packadd mini.align' '+packadd onedark.nvim' \
      '+helptags ALL' '+qa!'
# Relocate the complete tree and hide system terminfo. Test only isolated state.
RUN --network=none mv /out/nvim /out/nvim-relocated \
    && cp -a /etc/terminfo /build/test-terminfo \
    && rm -rf /etc/terminfo /lib/terminfo /usr/share/terminfo \
    && python3 /build/smoke-test.py /out/nvim-relocated/bin/nvim \
    && mv /out/nvim-relocated /out/nvim
FROM scratch AS minimal-test
COPY --from=builder /out/nvim /nvim
COPY smoke-test.lua nvim-tree-test.lua enhancements-test.lua /
ENV HOME=/test XDG_CONFIG_HOME=/test/config XDG_DATA_HOME=/test/data \
    XDG_STATE_HOME=/test/state XDG_CACHE_HOME=/test/cache \
    TEST_ROOT=/test NVIM_NO_SHELL=1 LANG=C.UTF-8
RUN --network=none ["/nvim/bin/nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", "/smoke-test.lua"]
RUN --network=none ["/nvim/bin/nvim", "--headless", "-u", "NONE", "-i", "NONE", "+lua if vim.fn.filereadable('/test/headless.ok') ~= 1 then vim.cmd('cquit 1') end", "+qa!"]
FROM scratch AS artifact
COPY --from=minimal-test /nvim /nvim
COPY --from=builder /out/sources /sources
