#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf 'Usage: %s /path/to/iotop /scratch/dir-on-disk\n' "$0" >&2
  exit 2
fi

iotop=$1
scratch=$(mktemp -d "$2/iotop-smoke.XXXXXXXX")
writer=''
producer=''
cleanup() {
  if [ -n "$producer" ]; then kill "$producer" 2>/dev/null || :; wait "$producer" 2>/dev/null || :; fi
  if [ -n "$writer" ]; then kill "$writer" 2>/dev/null || :; wait "$writer" 2>/dev/null || :; fi
  rm -rf -- "$scratch"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

export HOME="$scratch" XDG_CONFIG_HOME="$scratch/config" LC_ALL=C
printf 'Kernel: %s\n' "$(uname -rm)"
"$iotop" --version
mkfifo "$scratch/input"
dd if="$scratch/input" of="$scratch/data" bs=16384 conv=fsync 2>"$scratch/writer.err" &
writer=$!
# Pace the input so the same writer PID is alive across several samples.
(
  count=0
  while [ "$count" -lt 160 ]; do
    dd if=/dev/zero bs=16384 count=1 2>/dev/null
    count=$((count + 1))
    sleep 0.05
  done
) >"$scratch/input" &
producer=$!

if ! timeout 6 "$iotop" -b -P -a -k -n 6 -d 0.25 --hide-vfs -p "$writer" \
    >"$scratch/batch.out" 2>"$scratch/batch.err"; then
  printf 'iotop batch command failed\n' >&2
  grep -H . "$scratch/batch.out" "$scratch/batch.err" "$scratch/writer.err" >&2 || :
  exit 1
fi
grep . "$scratch/batch.err" >&2 || :

if ! awk '$1 == "write_bytes:" && $2 > 0 { seen = 1; print } END { exit !seen }' "/proc/$writer/io"; then
  printf 'Writer did not record disk I/O; use a disk-backed scratch directory\n' >&2
  grep . "$scratch/writer.err" >&2 || :
  exit 1
fi
# With --hide-vfs the disk-write value follows PID, priority, user and read value/unit.
if ! awk -v pid="$writer" '$1 == pid && $6 > 0 { seen = 1; print } END { exit !seen }' "$scratch/batch.out"; then
  printf 'iotop did not report positive disk writes for PID %s\n' "$writer" >&2
  grep . "$scratch/batch.out" >&2 || :
  exit 1
fi
