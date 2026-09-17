#!/usr/bin/env bash
set -euo pipefail

input="$1"
output="$2"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

rpgmasd decrypt --file "$input" --output-dir "$tmp_dir" >/dev/null
source_file="$tmp_dir/$(basename -- "${input%.*}").png"
install -m644 "$source_file" "$output"
