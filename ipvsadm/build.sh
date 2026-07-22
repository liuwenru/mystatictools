#!/usr/bin/env bash
# Local helper: build ipvsadm static (musl) image and extract binaries.
# Output is isolated per-host-kernel into bin_$(uname -r)/.
#
# Usage:
#   ./build.sh                       # build for current arch
#   ./build.sh linux/arm64           # build for specified platform
#   ./build.sh "" ipvsadm:dev        # custom image tag
#   KVER=5.10.0 ./build.sh           # override kernel version subdir
set -euo pipefail

PLATFORM="${1:-}"
TAG="${2:-ipvsadm:dev}"
KVER="${KVER:-$(uname -r)}"
OUT_DIR="bin_${KVER}"

cd "$(dirname "$0")"

if [[ -n "$PLATFORM" ]]; then
    docker buildx build --platform "$PLATFORM" -t "$TAG" --load .
else
    docker buildx build -t "$TAG" --load .
fi

echo "==> Extracting binaries to ./${OUT_DIR}/"
mkdir -p "$OUT_DIR"
cid=$(docker create "$TAG")
for b in ipvsadm ipvsadm-save ipvsadm-restore; do
    docker cp "$cid:/usr/sbin/$b" "${OUT_DIR}/${b}"
done
docker rm "$cid" >/dev/null

echo "==> Done. Binaries:"
ls -la "${OUT_DIR}/"
file "${OUT_DIR}/ipvsadm"