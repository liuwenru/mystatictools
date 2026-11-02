#!/bin/bash
set -e
cd "$(dirname "$0")"

cp dist/x86_64/rsync /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/
cp dist/aarch64/rsync /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
