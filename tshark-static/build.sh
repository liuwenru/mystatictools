#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir=${1:-"${script_dir}/dist"}

mkdir -p "${output_dir}"
docker buildx build \
    --output "type=local,dest=${output_dir}" \
    "${script_dir}"
