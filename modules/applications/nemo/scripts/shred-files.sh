#!/usr/bin/env bash
set -euo pipefail

files=("$@")
count="${#files[@]}"

if [[ $count -eq 0 ]]; then
	zenity --error \
		--title="Shred files" \
		--text="No files were selected." \
		2>/dev/null || true
	exit 1
fi

if [[ $count -eq 1 ]]; then
	msg="Permanently shred \"$(basename -- "${files[0]}")\"? This cannot be undone."
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

invalid_files=()

for file in "${files[@]}"; do
	if [[ -f $file ]]; then
		shred -u "$file"
		continue
	fi

	invalid_files+=("$file")
done

if [[ ${#invalid_files[@]} -gt 0 ]]; then
	zenity --warning \
		--title="Shred files" \
		--text="Skipped ${#invalid_files[@]} item(s) that are not regular files." \
		2>/dev/null || true
fi
