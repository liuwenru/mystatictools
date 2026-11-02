#!/bin/bash
set -e
cd "$(dirname "$0")"

cp dist/x86_64/pstree /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/
cp dist/x86_64/procs /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/
cp dist/aarch64/pstree /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
cp dist/aarch64/procs /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
