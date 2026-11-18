ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG LRZSZ_VERSION=0.13.1
ARG LRZSZ_SHA256=112f91059fbd118e016d800c1a5c5a1702e965d8b9bfbda6015e44e20bfb93c9
ARG TARGETARCH
ARG JOBS=4

RUN apk add --no-cache build-base python3
WORKDIR /build/lrzsz
# 官方发行包随构建文件保存，重建时不依赖上游下载站。
COPY sources/lrzsz-${LRZSZ_VERSION}.tar.gz /tmp/lrzsz.tar.gz
RUN printf '%s  %s\n' "${LRZSZ_SHA256}" /tmp/lrzsz.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/lrzsz.tar.gz --strip-components=1 \
    && CFLAGS=-O2 LDFLAGS=-static ./configure --prefix=/usr --disable-nls \
    && make -j"${JOBS}" \
    && mkdir -p /out \
    && cp src/lrz src/lsz /out/ \
    && strip /out/lrz /out/lsz \
    && cp COPYING man/lrz.1 man/lsz.1 /out/ \
    && cd /out \
    && ln -s lrz rz && ln -s lrz rx && ln -s lrz rb \
    && ln -s lrz lrx && ln -s lrz lrb \
    && ln -s lsz sz && ln -s lsz sx && ln -s lsz sb \
    && ln -s lsz lsx && ln -s lsz lsb

RUN for f in /out/lrz /out/lsz; do \
      readelf -h "$f" > /tmp/header; \
      case "${TARGETARCH}" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/header ;; \
        *) exit 1 ;; \
      esac || exit 1; \
      readelf -l "$f" > /tmp/program || exit 1; \
      ! grep -q INTERP /tmp/program || exit 1; \
      readelf -d "$f" > /tmp/dynamic || exit 1; \
      ! grep -q '(NEEDED)' /tmp/dynamic || exit 1; \
      "$f" --version | grep -F "${LRZSZ_VERSION}" || exit 1; \
    done

COPY test/transfer.py /build/transfer.py
# Python 仅为外部测试驱动；子进程 chroot 内只有静态二进制和样例，没有共享库或 shell。
RUN python3 /build/transfer.py /out \
    && cd /out \
    && sha256sum lrz lsz rz sz rx sx rb sb lrx lsx lrb lsb COPYING lrz.1 lsz.1 > SHA256SUMS

FROM scratch AS artifact
COPY --from=builder /out/ /
