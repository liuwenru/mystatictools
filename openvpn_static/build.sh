#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir="${project_dir}/dist"

rm -rf "${output_dir}"
docker build \
    --target artifact \
    --output "type=local,dest=${output_dir}" \
    "$@" \
    "${project_dir}"

chmod 0755 "${output_dir}/openvpn"
"${output_dir}/openvpn" --version
