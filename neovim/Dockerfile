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
RUN for tool in /out/nvim/libexec/* /out/nvim/libexec/typescript/lib/tsc /out/nvim/libexec/node/bin/node; do \
      case "$tool" in *.py) continue ;; esac; \
      if [ -d "$tool" ]; then continue; fi; \
      strip "$tool"; file "$tool"; \
      if readelf -l "$tool" | grep -q INTERP; then exit 1; fi; \
      if readelf -d "$tool" | grep -q '(NEEDED)'; then exit 1; fi; \
      case "${TARGETARCH}" in \
        amd64) readelf -h "$tool" | grep -q 'Advanced Micro Devices X86-64' ;; \
        arm64) readelf -h "$tool" | grep -q AArch64 ;; \
        *) exit 1 ;; \
      esac || exit 1; \
    done
# Node 写的语言服务器：用随包静态 node 自带的 npm 按 package-lock.json 安装，npm ci 校验每个包的 integrity。
# --ignore-scripts：依赖中只有 core-js 有 postinstall，内容是打印赞助信息。
# 静态 node 不能加载 .node 原生扩展，安装后确认没有 .node 文件。
# --no-bin-links：配置直接用 node 执行入口脚本，不需要 .bin；软链接在 ARM 端经 SSHFS 导出会失败。
COPY lsp-node/package.json lsp-node/package-lock.json /out/nvim/libexec/lsp-node/
WORKDIR /out/nvim/libexec/lsp-node
RUN /build/node-dist/bin/node /build/node-dist/lib/node_modules/npm/bin/npm-cli.js ci \
      --ignore-scripts --omit=dev --no-audit --no-fund --no-update-notifier --no-bin-links \
      --fetch-retries=5 --cache /tmp/npm-cache --registry=https://registry.npmjs.org/ \
    && rm -rf /tmp/npm-cache \
    && ! find . -name '*.node' | grep . \
    && ! find . -type l | grep . \
    && test -f node_modules/yaml-language-server/bin/yaml-language-server \
    && test -f node_modules/vscode-langservers-extracted/bin/vscode-json-language-server \
    && test -f node_modules/bash-language-server/out/cli.js
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
COPY test/ /build/test/
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
COPY Dockerfile build.sh fetch-deps.py static-parsers.py bundle-sources.py generate-completion.py init-offline.lua biome-jsonc.json README.md /out/sources/build/
COPY completion/ /out/sources/build/completion/
COPY lsp-node/ /out/sources/build/lsp-node/
COPY doc/ /out/sources/build/doc/
RUN python3 /out/sources/build/generate-completion.py --check
COPY test/ /out/sources/build/test/
RUN python3 /out/sources/build/test/dictionary-generation-test.py
COPY --from=extras /out/nvim/ /out/nvim/
COPY biome-jsonc.json /out/nvim/libexec/biome-jsonc.json
COPY completion/init.lua completion/README.md /out/nvim/completion/
COPY completion/generated/ /out/nvim/completion/generated/
COPY completion/custom/ /out/nvim/completion/custom/
COPY completion/licenses/ /out/nvim/completion/licenses/
# 官方 Compose schema 快照（哈希在 completion/sources.json，构建时 generate-completion.py --check 已校验），供 yaml 服务器使用。
COPY completion/sources/compose.json /out/nvim/completion/schemas/
COPY doc/ /out/nvim/share/nvim/runtime/doc/
COPY --from=extras /out/sources/ /out/sources/
COPY extras.json fetch-extras.py /out/sources/build/
RUN /out/nvim/bin/nvim --headless -u NONE -i NONE \
      '+packadd conform.nvim' '+packadd indent-blankline.nvim' '+packadd mini.align' '+packadd onedark.nvim' \
      '+helptags ALL' '+qa!'
# Relocate the complete tree and hide system terminfo. Test only isolated state.
RUN --network=none mv /out/nvim /out/nvim-relocated \
    && cp -a /etc/terminfo /build/test-terminfo \
    && rm -rf /etc/terminfo /lib/terminfo /usr/share/terminfo \
    && python3 /build/test/smoke-test.py /out/nvim-relocated/bin/nvim \
    && mv /out/nvim-relocated /out/nvim
FROM scratch AS minimal-test
COPY --from=builder /out/nvim /nvim
COPY test/*.lua /tests/
ENV HOME=/test XDG_CONFIG_HOME=/test/config XDG_DATA_HOME=/test/data \
    XDG_STATE_HOME=/test/state XDG_CACHE_HOME=/test/cache \
    TEST_ROOT=/test NVIM_NO_SHELL=1 LANG=C.UTF-8
RUN --network=none ["/nvim/bin/nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", "/tests/smoke-test.lua"]
RUN --network=none ["/nvim/bin/nvim", "--headless", "-u", "NONE", "-i", "NONE", "+lua if vim.fn.filereadable('/test/headless.ok') ~= 1 then vim.cmd('cquit 1') end", "+qa!"]
RUN --network=none ["/nvim/bin/nvim", "--headless", "-u", "/nvim/examples/init.lua", "-i", "NONE", "-c", "lua local ok, err = pcall(dofile, '/tests/completion-test.lua'); if not ok then print(err); vim.cmd('cquit 1') end"]
# 随包语言服务器：scratch 中没有 shell、libc、Python、系统 Node，且断网。
RUN --network=none ["/nvim/bin/nvim", "--headless", "-u", "/nvim/examples/init.lua", "-i", "NONE", "-c", "lua local ok, err = pcall(dofile, '/tests/lsp-bundled-test.lua'); if not ok then print(err); vim.cmd('cquit 1') end"]
RUN --network=none ["/nvim/bin/nvim", "--headless", "-u", "NONE", "-i", "NONE", "+lua if vim.fn.filereadable('/test/lsp-bundled.ok') ~= 1 then vim.cmd('cquit 1') end", "+qa!"]
FROM scratch AS artifact
COPY --from=minimal-test /nvim /nvim
COPY --from=builder /out/sources /sources
