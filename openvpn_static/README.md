# OpenVPN musl static build

This builds OpenVPN 2.6 with Alpine Linux and exports a statically linked musl
binary to `dist/openvpn`.

## Build

```sh
./build.sh
```

The output architecture follows the Docker host. To build explicitly for
x86-64 or ARM64 with a configured BuildKit emulator:

```sh
./build.sh --platform linux/amd64
./build.sh --platform linux/arm64
```

Versions can be overridden with build arguments:

```sh
./build.sh \
  --build-arg ALPINE_VERSION=3.22 \
  --build-arg OPENVPN_VERSION=2.6.21 \
  --build-arg OPENVPN_SHA256=24cb6185e544a47323d6798b03d39f2367d96f227bee9cd1543e8ed528319b17
```

When changing the OpenVPN version, its matching source archive SHA-256 must
also be supplied.

## Run

OpenVPN still needs root privileges (or equivalent capabilities) and a kernel
TUN device:

```sh
sudo ./dist/openvpn --config client.ovpn
```

Basic interface and route setup uses OpenVPN's built-in Linux netlink support.
Profiles using `up`, `down`, or DNS helper scripts still require those external
scripts and their interpreters.

The binary includes OpenSSL, LZO, LZ4, and musl. DCO, systemd integration,
loadable plugins, and PKCS#11 are disabled to keep the artifact self-contained
and avoid runtime-loaded dependencies.
