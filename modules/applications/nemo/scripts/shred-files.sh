#!/usr/bin/env bash
set -euo pipefail

files=("$@")
count="${#files[@]}"

if [[ $count -eq 1 ]]; then
	msg="Permanently shred \"$(basename "${files[0]}")\"? This cannot be undone."
else
	msg="Permanently shred $count files? This cannot be undone."
fi

zenity --question \
	--title="Shred files" \
	--text="$msg" \
	--ok-label="Shred" \
	--cancel-label="Cancel" \
	--icon-name=dialog-warning \
	2>/dev/null || exit 0

for file in "${files[@]}"; do
	shred -u "$file"
done
