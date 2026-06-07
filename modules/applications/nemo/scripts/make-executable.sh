#!/usr/bin/env bash
set -euo pipefail

files=()

for item in "$@"; do
	if [[ -f $item ]]; then
		files+=("$item")
	fi
done

if [[ ${#files[@]} -eq 0 ]]; then
	zenity --error \
		--title="Make executable" \
		--text="No regular files were selected." \
		2>/dev/null || true
	exit 1
fi

chmod_path="$(command -v chmod)"
pkexec "$chmod_path" a+x -- "${files[@]}"
