#!/usr/bin/env bash
set -euo pipefail

target_ext="$1"
shift

for file in "$@"; do
	base="${file%.*}"
	out="${base}.${target_ext}"

	if [[ $out == "$file" ]]; then
		echo "Skipping $file: already ${target_ext}" >&2
		continue
	fi

	magick "$file" "$out"
done
