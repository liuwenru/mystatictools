ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION} AS builder

ARG PY_SPY_VERSION=0.4.2
ARG PY_SPY_SHA256=ecf8d945f63b172126abcd68e21f3e5f250498cb774d88247d80a6f2cacdb998
ARG TARGETARCH

# libunwind/xz/zlib static archives are needed by `--native` (feature unwind).
RUN for i in 1 2 3 4; do \
        apk add --no-cache build-base cargo curl file rust \
            libunwind-dev libunwind-static xz-dev xz-static zlib-static \
        && break; \
        [ "$i" = 4 ] && exit 1; sleep 5; \
    done

WORKDIR /build/py-spy
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/py-spy.tar.gz \
        "https://github.com/benfred/py-spy/archive/refs/tags/v${PY_SPY_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${PY_SPY_SHA256}" /tmp/py-spy.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/py-spy.tar.gz --strip-components=1

# Alpine's rust target is *-alpine-linux-musl, so remoteprocess's build.rs emits
# dylib=lzma,unwind,unwind-ptrace,unwind-<arch> instead of copying archives from
# /usr/local/musl (only present in upstream's CI image). rustc wraps those in
# -Bdynamic, so:
# - remove the link-time .so symlinks (builder only) so ld falls back to .a;
# - append -Bstatic -lunwind -llzma: the order above is wrong for static
#   archives (lzma first; _U<arch>_setcontext is in libunwind.a);
# - pass --target explicitly so crt-static skips build scripts and proc-macros.
ENV CARGO_NET_RETRY=10 \
    CARGO_PROFILE_RELEASE_STRIP=symbols \
    RUSTFLAGS="-C target-feature=+crt-static -C link-arg=-Wl,-Bstatic -C link-arg=-lunwind -C link-arg=-llzma"
RUN rm -f /usr/lib/libunwind*.so /usr/lib/liblzma.so \
    && target=$(rustc -vV | sed -n 's/^host: //p') \
    && cargo build --release --locked --features unwind --target "$target" \
    && mkdir -p /out \
    && cp "target/$target/release/py-spy" /out/py-spy \
    && file /out/py-spy \
    && case "${TARGETARCH}" in \
        amd64) readelf -h /out/py-spy | grep -q 'Machine:.*X86-64' ;; \
        arm64) readelf -h /out/py-spy | grep -q 'Machine:.*AArch64' ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && readelf -l /out/py-spy > /tmp/elf-program-headers \
    && ! grep -q INTERP /tmp/elf-program-headers \
    && readelf -d /out/py-spy > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/py-spy --version | grep -Fx "py-spy ${PY_SPY_VERSION}" \
    && /out/py-spy record --help | grep -q -- '--native'

FROM scratch AS artifact
COPY --from=builder /out/py-spy /py-spy
COPY --from=builder /build/py-spy/LICENSE /LICENSE.py-spy
