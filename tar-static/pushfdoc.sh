#!/bin/bash
set -e
cd "$(dirname "$0")"

cp dist/x86_64/tar /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/
cp dist/x86_64/bsdtar /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/
cp dist/x86_64/bsdunzip /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/
cp dist/aarch64/tar /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
cp dist/aarch64/bsdtar /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
cp dist/aarch64/bsdunzip /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
