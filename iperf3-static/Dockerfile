ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG IPERF_VERSION=3.22
ARG IPERF_SHA256=1c0d0fb02c52626111d6e132db80edfbf27bbaff8bd9245df2a371dcb0b35a92
ARG TARGETARCH
ARG JOBS=4

# OpenSSL 用于 RSA 认证，lksctp-tools 提供 SCTP 头文件和 sctp_bindx。
RUN apk add --no-cache build-base linux-headers curl file python3 openssl \
        openssl-dev openssl-libs-static lksctp-tools-dev lksctp-tools-static
WORKDIR /build
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/iperf.tar.gz \
        "https://github.com/esnet/iperf/releases/download/${IPERF_VERSION}/iperf-${IPERF_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${IPERF_SHA256}" /tmp/iperf.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/iperf.tar.gz
WORKDIR /build/iperf-${IPERF_VERSION}
RUN ./configure --disable-shared --enable-static --enable-static-bin \
        --with-openssl=/usr \
    && grep -q '^#define HAVE_SSL 1' src/iperf_config.h \
    && grep -q '^#define HAVE_SCTP_H 1' src/iperf_config.h \
    && make -j"${JOBS}" \
    && make check \
    && mkdir -p /out \
    && cp src/iperf3 /out/iperf3 \
    && cp src/iperf3.1 LICENSE /out/ \
    && strip /out/iperf3 \
    && file /out/iperf3 \
    && readelf -h /out/iperf3 > /tmp/elf-header \
    && case "${TARGETARCH}" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && readelf -l /out/iperf3 > /tmp/elf-program \
    && ! grep -q INTERP /tmp/elf-program \
    && readelf -d /out/iperf3 > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/iperf3 --version | tee /tmp/version \
    && grep -F "iperf ${IPERF_VERSION}" /tmp/version \
    && grep -F 'SCTP' /tmp/version \
    && grep -F 'authentication' /tmp/version

COPY test/smoke-test.py /build/smoke-test.py
RUN python3 /build/smoke-test.py /out/iperf3

FROM scratch AS artifact
COPY --from=builder /out/ /
