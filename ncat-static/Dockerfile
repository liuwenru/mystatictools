ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder
ARG NMAP_VERSION=7.993
ARG NMAP_SHA256=270e55f04915bfcecb5db8feb959d4c5ba86a48c094520a4f1c07571e1c79c59
ARG TARGETARCH
ARG JOBS=4

# OpenSSL 用于 --ssl；linux-headers 提供 vsock 头文件。
# openssl 命令、perl 模块、python3 只用于测试，不进运行包。
RUN apk add --no-cache build-base linux-headers curl file openssl openssl-dev openssl-libs-static \
        perl perl-socket6 perl-http-message perl-uri python3
WORKDIR /build
RUN curl --fail --location --retry 4 --retry-all-errors \
        --output /tmp/nmap.tar.bz2 "https://nmap.org/dist/nmap-${NMAP_VERSION}.tar.bz2" \
    && printf '%s  %s\n' "${NMAP_SHA256}" /tmp/nmap.tar.bz2 | sha256sum -c - \
    && tar -xjf /tmp/nmap.tar.bz2
WORKDIR /build/nmap-${NMAP_VERSION}
# 本地补丁（监听模式的三处问题：单 socket --recv-only 立即退出、TLS 半条记录误判为 EOF、
# 代理服务端忽略监听地址），原因见 patches/ 内各文件开头。
COPY patches/ /build/patches/
RUN for p in /build/patches/*.patch; do patch -p1 --forward < "$p" || exit 1; done

# Ncat 在 Nmap 源码树内，依赖同树的 nbase、nsock 和自带 Lua 5.4（--lua-exec）。
# 顶层 configure 只为生成这些子目录的配置，只编译 ncat，不编译 nmap 本体。
# --prefix=/usr 决定编译进程序的 ca-bundle.crt 路径 /usr/share/ncat/ca-bundle.crt。
RUN LDFLAGS=-static ./configure --prefix=/usr --with-openssl=/usr --with-liblua=included \
        --with-libpcap=included --without-libssh2 --without-zenmap --without-ndiff --without-nping \
    && grep -q '^#define HAVE_OPENSSL 1' ncat/config.h \
    && grep -q '^#define HAVE_LINUX_VM_SOCKETS_H 1' ncat/config.h \
    && make -j"${JOBS}" build-ncat \
    && test -f ncat/ncat_lua.o \
    && strings ncat/ncat | grep -qx '/usr/share/ncat/ca-bundle.crt'

# 上游测试：单元测试 + ncat-test.pl（外部行为），断网运行。
# - 构建网络的 DNS 若对任意名字都返回地址（代理软件 fake-IP），addrset 中“非法地址应解析失败”的
#   20 项会误报；断网后 /etc/hosts 只读，3 项 scanme.nmap.org 名字解析用例改用 localhost。
# - 源码包里的 test-cert.pem 已于 2026-08-30 过期，脚本发现过期会重新生成后直接 exit 1，这里先生成。
# - 脚本用 kill -$$ 结束子进程，perl 必须是进程组组长，否则 waitpid 一直等待，所以用 setsid 启动。
# - 允许失败的两项：
#   Unix DGRAM：客户端读到 stdin EOF 立即删除自己的源 socket，服务端随后 connect 回去报
#   No such file or directory；Alpine 的 nmap-ncat 7.97、Fedora 的 7.92 结果相同，属上游行为。
#   HTTP CONNECT IPv6 client, IPv4 server：用例以 `ncat 127.0.0.1 端口 -l --proxy-type http` 启动代理
#   再从 ::1 连接，依赖监听地址被忽略；proxy-server-listen-address.patch 后代理只监听 127.0.0.1。
RUN --network=none sed -i 's/scanme\.nmap\.org/localhost/g' ncat/test/test-addrset.sh \
    && make -C ncat check \
    && cd ncat/test \
    && openssl req -new -x509 -nodes -days 3650 -subj /O=ncat-test/CN=localhost/ \
        -keyout test-cert.pem -out test-cert.pem 2>/dev/null \
    && { setsid perl ncat-test.pl > /tmp/ncat-test.log 2>&1 || true; } \
    && cat /tmp/ncat-test.log \
    && ! grep -q 'unexpected passes' /tmp/ncat-test.log \
    && ! grep '^FAIL ' /tmp/ncat-test.log \
        | grep -vxF -e 'FAIL Server UNIX socket listen on ncat.unixsock --udp (DGRAM)' \
            -e 'FAIL HTTP CONNECT IPv6 client, IPv4 server' \
    && grep -Eq '^[012] unexpected failures\.$' /tmp/ncat-test.log

RUN mkdir -p /out \
    && cp ncat/ncat ncat/docs/ncat.1 ncat/certs/ca-bundle.crt LICENSE /out/ \
    && strip /out/ncat \
    && file /out/ncat \
    && readelf -h /out/ncat > /tmp/elf-header \
    && case "${TARGETARCH}" in \
        amd64) grep -q 'Machine:.*X86-64' /tmp/elf-header ;; \
        arm64) grep -q 'Machine:.*AArch64' /tmp/elf-header ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && readelf -l /out/ncat > /tmp/elf-program \
    && ! grep -q INTERP /tmp/elf-program \
    && readelf -d /out/ncat > /tmp/elf-dynamic \
    && ! grep -q '(NEEDED)' /tmp/elf-dynamic \
    && /out/ncat --version 2>&1 | tee /tmp/version \
    && grep -F "Ncat: Version ${NMAP_VERSION} " /tmp/version

COPY test/ /build/test/
RUN python3 /build/test/smoke-test.py /out

FROM scratch AS artifact
COPY --from=builder /out/ /
