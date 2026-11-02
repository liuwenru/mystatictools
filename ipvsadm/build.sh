#!/usr/bin/env bash
# Local helper: build ipvsadm static (musl) image and extract binaries.
# Output is isolated per-target-architecture into dist/amd64 or dist/arm64.
#
# Usage:
#   ./build.sh                       # build for current arch
#   ./build.sh linux/arm64           # build for specified platform
#   ./build.sh "" ipvsadm:dev        # custom image tag
set -euo pipefail

PLATFORM="${1:-}"
TAG="${2:-ipvsadm:dev}"
ARCH="${PLATFORM:-$(uname -m)}"
case "$ARCH" in
    amd64|x86_64|linux/amd64) ARCH=amd64 ;;
    arm64|aarch64|linux/arm64) ARCH=arm64 ;;
    *) echo "Unsupported platform: $ARCH" >&2; exit 2 ;;
esac
PLATFORM="linux/${ARCH}"
OUT_DIR="dist/${ARCH}"

cd "$(dirname "$0")"

docker buildx build --builder default --platform "$PLATFORM" -t "$TAG" --load .

echo "==> Extracting binaries to ./${OUT_DIR}/"
mkdir -p "$OUT_DIR"
cid=$(docker create "$TAG")
trap 'docker rm "$cid" >/dev/null' EXIT
for b in ipvsadm ipvsadm-save ipvsadm-restore; do
    docker cp "$cid:/usr/sbin/$b" "${OUT_DIR}/${b}"
done
docker rm "$cid" >/dev/null
trap - EXIT
(cd "$OUT_DIR" && sha256sum ipvsadm ipvsadm-save ipvsadm-restore > SHA256SUMS)

echo "==> Done. Binaries:"
ls -la "${OUT_DIR}/"
file "${OUT_DIR}/ipvsadm"
