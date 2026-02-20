#!/usr/bin/env bash
# Nemo action: extract archive into a folder, mimicking Windows behaviour.
#
# - If the archive has a single root entry, extract directly to the parent
#   directory so the archive's own folder name is used (no double-wrapping).
# - If the archive has multiple root entries, wrap them in a new folder
#   named after the archive file.
set -euo pipefail

file="$1"
parent="$(dirname "$file")"

# Count unique top-level entries using -slt (machine-readable output).
# Skip the first Path line which is the archive file itself.
top_entries=$(7z l -slt "$file" \
  | grep "^Path = " \
  | tail -n +2 \
  | sed 's|^Path = ||' \
  | cut -d'/' -f1 \
  | sort -u)
top_count=$(echo "$top_entries" | grep -c .)

if [[ "$top_count" -eq 1 ]]; then
  # Single root entry: extract directly to parent (no double-wrapping).
  7z x -y "$file" -o"$parent"
else
  # Multiple root entries: wrap in a folder named after the archive.
  name=$(basename "$file")
  for ext in .tar.gz .tar.bz2 .tar.xz .tar.zst .tar.lz4; do
    orig="$name"
    name="${name%$ext}"
    [[ "$name" != "$orig" ]] && break
  done
  name="${name%.*}"
  7z x -y "$file" -o"$parent/$name"
fi
