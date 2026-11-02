ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG SEVENZIP_VERSION=26.05
ARG SEVENZIP_SOURCE=2605
ARG SEVENZIP_SHA256=0b6080b8c3e7a579161d2d495224c0e51c467576cb4c7048b0ab485ef44cc22e
ARG TARGETARCH
ARG JOBS=4

RUN apk add --no-cache build-base linux-headers curl xz file python3
WORKDIR /build/7zip
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/7zip.tar.xz \
        "https://github.com/ip7z/7zip/releases/download/${SEVENZIP_VERSION}/7z${SEVENZIP_SOURCE}-src.tar.xz" \
    && printf '%s  %s\n' "${SEVENZIP_SHA256}" /tmp/7zip.tar.xz | sha256sum -c - \
    && tar -xJf /tmp/7zip.tar.xz
RUN case "${TARGETARCH}" in \
        amd64) makefile=../../cmpl_gcc.mak ;; \
        arm64) makefile=../../cmpl_gcc_arm64.mak ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && make -C CPP/7zip/Bundles/Alone2 -j"${JOBS}" -f "$makefile" O=_o LDFLAGS_STATIC_2=-static \
    && mkdir -p /out \
    && cp CPP/7zip/Bundles/Alone2/_o/7zz /out/7zz \
    && cp DOC/License.txt DOC/copying.txt DOC/unRarLicense.txt /out/ \
    && strip /out/7zz \
    && file /out/7zz \
    && readelf -h /out/7zz > /tmp/elf-header \
    && case "${TARGETARCH}" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
    esac \
    && readelf -l /out/7zz > /tmp/elf-program \
    && ! grep -q INTERP /tmp/elf-program \
    && readelf -d /out/7zz > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/7zz i | grep -F "7-Zip (z) ${SEVENZIP_VERSION}"

COPY test/smoke-test.py /build/smoke-test.py
RUN python3 /build/smoke-test.py /out/7zz

FROM scratch AS artifact
COPY --from=builder /out/ /
