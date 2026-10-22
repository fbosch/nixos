#!/usr/bin/env bash
set -euo pipefail
umask 077

image=$1
size_bytes=$2

if [[ -e $image || -L $image ]]; then
  if [[ ! -f $image || -L $image ]]; then
    echo "Refusing a non-regular cache image: $image" >&2
    exit 1
  fi
  if [[ $(stat -c %s -- "$image") != "$size_bytes" ]]; then
    echo "Cache image size changed; explicitly recreate the unmounted disposable cache before resizing." >&2
    exit 1
  fi
  if [[ $(blkid -p -s TYPE -o value -- "$image") != ext4 ]]; then
    echo "Refusing to format an existing cache image: $image" >&2
    exit 1
  fi
  exit 0
fi

temporary=$(mktemp "${image}.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
truncate --size="$size_bytes" -- "$temporary"
mkfs.ext4 -q -F -m 0 -L nas-downloads \
  -E lazy_itable_init=0,lazy_journal_init=0 "$temporary"
sync --data -- "$temporary"
# Publish without replacing a file created by another initializer.
ln -- "$temporary" "$image"
