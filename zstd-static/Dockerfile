ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder

ARG ZSTD_VERSION=1.5.7
ARG ZSTD_SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
ARG TARGETARCH

RUN apk add --no-cache build-base curl file python3
WORKDIR /build/zstd
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/zstd.tar.gz \
        "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${ZSTD_SHA256}" /tmp/zstd.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/zstd.tar.gz --strip-components=1 \
    && make -C contrib/pzstd -j"$(getconf _NPROCESSORS_ONLN)" \
        CFLAGS="-O2 -Wno-deprecated-declarations" CXXFLAGS="-O2" LDFLAGS="-static" \
    && mkdir -p /out \
    && cp contrib/pzstd/pzstd /out/pzstd \
    && strip /out/pzstd \
    && file /out/pzstd \
    && readelf -h /out/pzstd \
    && case "${TARGETARCH}" in \
        amd64) readelf -h /out/pzstd | grep -q 'Machine:.*X86-64' ;; \
        arm64) readelf -h /out/pzstd | grep -q 'Machine:.*AArch64' ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && readelf -l /out/pzstd > /tmp/elf-program-headers \
    && ! grep -q INTERP /tmp/elf-program-headers \
    && readelf -d /out/pzstd > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/pzstd --version 2>&1 | grep -F "PZSTD version: ${ZSTD_VERSION}."

# Standard zstd is only a test peer, not part of the delivered binary.
RUN make -C programs -j"$(getconf _NPROCESSORS_ONLN)" zstd
COPY smoke-test.py /build/smoke-test.py
RUN python3 /build/smoke-test.py /out/pzstd /build/zstd/programs/zstd

FROM scratch AS artifact
COPY --from=builder /out/pzstd /pzstd
COPY --from=builder /build/zstd/LICENSE /LICENSE.zstd
