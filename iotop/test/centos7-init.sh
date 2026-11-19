#!/bin/sh
set -eu
export PATH=/bin
/bin/busybox --install -s /bin
trap 'poweroff -f' EXIT
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts
for mod in virtio virtio_ring virtio_pci virtio_blk mbcache jbd2 ext4; do
  insmod "/ko/$mod.ko"
done
mount -t ext4 -o sync /dev/vda /disk
/batch-io.sh /iotop /disk

export HOME=/tmp XDG_CONFIG_HOME=/tmp/config TERMINFO=/tmp TERMINFO_DIRS=/tmp LINES=30 COLUMNS=120
for term in xterm-256color tmux-256color xterm-kitty; do
  export TERM="$term" LC_ALL=C.UTF-8
  (sleep 1; printf q) | timeout 8 script -q -c 'stty rows 30 cols 120; /iotop -d 0.25 && printf "\nUI_EXIT_OK\n"' \
    /tmp/pty.log >/dev/null
  grep -q 'DISK WRITE' /tmp/pty.log
  grep -q '^UI_EXIT_OK' /tmp/pty.log
  printf 'Interactive without terminfo: %s\n' "$term"
done
printf 'IOTOP_CENTOS7_PASS\n'
