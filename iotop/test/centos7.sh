#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf 'Usage: %s /path/to/iotop /path/to/static-busybox\n' "$0" >&2
  exit 2
fi

test_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
kernel=3.10.0-1160.el7.x86_64
scratch=$(mktemp -d "${TMPDIR:-/tmp}/iotop-centos7.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$scratch/rpm" "$scratch/root/bin" "$scratch/root/dev" "$scratch/root/proc" \
  "$scratch/root/sys" "$scratch/root/disk" "$scratch/root/ko" "$scratch/root/tmp"
curl -fsSL --retry 4 --retry-all-errors -o "$scratch/kernel.rpm" \
  "https://vault.centos.org/7.9.2009/os/x86_64/Packages/kernel-$kernel.rpm"
printf '%s  %s\n' 4a74ed8e2ec25ff2f90a460ace450f1f5f9d8ec2388840ac54190eadc8a43575 \
  "$scratch/kernel.rpm" | sha256sum -c -
rpm2cpio "$scratch/kernel.rpm" > "$scratch/kernel.cpio"
(
  cd "$scratch/rpm"
  cpio -id --quiet './boot/vmlinuz-*' './lib/modules/*' < "$scratch/kernel.cpio"
)
for mod in virtio virtio_ring virtio_pci virtio_blk mbcache jbd2 ext4; do
  path=$(find "$scratch/rpm/lib/modules/$kernel" -name "$mod.ko.xz")
  xz -dc "$path" > "$scratch/root/ko/$mod.ko"
done
install -m 0755 "$1" "$scratch/root/iotop"
install -m 0755 "$2" "$scratch/root/bin/busybox"
install -m 0755 "$test_dir/batch-io.sh" "$scratch/root/batch-io.sh"
install -m 0755 "$test_dir/centos7-init.sh" "$scratch/root/init"
ln -s busybox "$scratch/root/bin/sh"
(
  cd "$scratch/root"
  find . -print0 | cpio --null --quiet -o -H newc > "$scratch/initramfs.cpio"
)
truncate -s 64M "$scratch/disk.img"
# Use ext4 features understood by the EL7 kernel, including on newer mkfs.ext4.
mkfs.ext4 -q -O '^metadata_csum,^metadata_csum_seed,^orphan_file,^64bit' "$scratch/disk.img"
if ! timeout 120 "${QEMU:-qemu-system-x86_64}" -machine pc,accel=kvm:tcg -m 512M -smp 2 -no-reboot \
    -display none -serial stdio -monitor none -nic none \
    -kernel "$scratch/rpm/boot/vmlinuz-$kernel" -initrd "$scratch/initramfs.cpio" \
    -append 'console=ttyS0 rdinit=/init panic=1 quiet' \
    -drive "file=$scratch/disk.img,format=raw,if=virtio" > "$scratch/serial.log" 2>&1; then
  grep . "$scratch/serial.log" >&2 || :
  exit 1
fi
grep . "$scratch/serial.log"
grep -q '^IOTOP_CENTOS7_PASS' "$scratch/serial.log"
