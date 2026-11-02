ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder

ARG DOS2UNIX_VERSION=7.5.7
ARG DOS2UNIX_SHA256=669ee27120ae71589f638fe3a167d6ea54f8633f5ab1b282551bd7a7c9510dfa
ARG TARGETARCH

RUN apk add --no-cache build-base curl file gettext python3 perl perl-test-simple
RUN apk add --no-cache gettext-dev gettext-static musl-locales
RUN apk add --no-cache perl-test-harness
RUN apk add --no-cache perl-utils
WORKDIR /build/dos2unix
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/dos2unix.tar.gz \
        "https://downloads.sourceforge.net/project/dos2unix/dos2unix/${DOS2UNIX_VERSION}/dos2unix-${DOS2UNIX_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${DOS2UNIX_SHA256}" /tmp/dos2unix.tar.gz | sha256sum -c - \
    && tar -xzf /tmp/dos2unix.tar.gz --strip-components=1 \
    && make -j"$(getconf _NPROCESSORS_ONLN)" LDFLAGS_USER=-static LIBS_EXTRA=-lintl \
        dos2unix unix2dos mac2unix unix2mac mofiles \
    && make -C test test UCS=1 \
    && mkdir -p /out \
    && cp dos2unix unix2dos /out/ \
    && ln -s dos2unix /out/mac2unix \
    && ln -s unix2dos /out/unix2mac \
    && strip /out/dos2unix /out/unix2dos \
    && make install-mo DESTDIR=/out \
    && cp COPYING.txt /out/LICENSE.dos2unix \
    && cp man/zh_CN/man1/dos2unix.txt /out/使用手册.txt \
    && for binary in /out/dos2unix /out/unix2dos; do \
        file "$binary"; \
        readelf -h "$binary"; \
        case "${TARGETARCH}" in \
            amd64) readelf -h "$binary" | grep -q 'Machine:.*X86-64' ;; \
            arm64) readelf -h "$binary" | grep -q 'Machine:.*AArch64' ;; \
            *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
        esac || exit 1; \
        readelf -l "$binary" > /tmp/elf-program-headers; \
        ! grep -q INTERP /tmp/elf-program-headers || exit 1; \
        readelf -d "$binary" > /tmp/elf-dynamic; \
        ! grep -q '(NEEDED)' /tmp/elf-dynamic || exit 1; \
        "$binary" --version 2>&1 | grep -F "${DOS2UNIX_VERSION}" || exit 1; \
    done

COPY smoke-test.py /build/smoke-test.py
RUN python3 /build/smoke-test.py /out

FROM scratch AS artifact
COPY --from=builder /out/ /
