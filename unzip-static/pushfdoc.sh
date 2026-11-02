#!/bin/bash
set -e
cd "$(dirname "$0")"

cp dist/x86_64/unzip /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/
cp dist/x86_64/funzip /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/
cp dist/x86_64/zipinfo /root/remotefs/fdoc.liuwenru/tools/static_tools/x86_64/

cp dist/aarch64/unzip /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
cp dist/aarch64/funzip /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
cp dist/aarch64/zipinfo /root/remotefs/fdoc.liuwenru/tools/static_tools/aarch64/
