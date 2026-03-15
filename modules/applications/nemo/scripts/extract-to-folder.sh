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
file_lower="$(basename "$file" | tr '[:upper:]' '[:lower:]')"

is_rar=false
if [[ $file_lower == *.rar ]]; then
	is_rar=true
fi

list_top_entries() {
	if [[ $is_rar == true ]]; then
		unrar lb -p- "$file" |
			awk -F'[\\\\/]' 'NF && $1 != "" { print $1 }' |
			sort -u
		return
	fi

	7z l -slt "$file" |
		grep "^Path = " |
		tail -n +2 |
		sed 's|^Path = ||' |
		cut -d'/' -f1 |
		sort -u
}

extract_archive() {
	local output_dir="$1"

	if [[ $is_rar == true ]]; then
		unrar x -idq -o+ -p- "$file" "$output_dir/"
		return
	fi

	7z x -y "$file" -o"$output_dir"
}

extract_with_progress() {
	local output_dir="$1"
	local status_file
	local cmd_pid
	local status
	local title="Extracting archive"
	local file_name
	local text
	file_name="$(basename "$file")"
	text="Extracting: $file_name"

	status_file="$(mktemp)"
	(
		set +e
		extract_archive "$output_dir"
		printf '%s\n' "$?" >"$status_file"
	) &
	cmd_pid=$!

	(
		while kill -0 "$cmd_pid" 2>/dev/null; do
			printf '# %s\n' "$text"
			sleep 0.2
		done
	) | zenity --progress \
		--title="$title" \
		--text="$text" \
		--pulsate \
		--auto-close \
		--no-cancel >/dev/null 2>&1 || true

	wait "$cmd_pid" || true
	read -r status <"$status_file" || status=1
	rm -f "$status_file"
	return "$status"
}

# Count unique top-level entries using -slt (machine-readable output).
# Skip the first Path line which is the archive file itself.
top_entries="$(list_top_entries)"
top_count=$(echo "$top_entries" | grep -c .)

if [[ $top_count -eq 1 ]]; then
	# Single root entry: extract directly to parent (no double-wrapping).
	extract_with_progress "$parent"
else
	# Multiple root entries: wrap in a folder named after the archive.
	name=$(basename "$file")
	for ext in .tar.gz .tar.bz2 .tar.xz .tar.zst .tar.lz4; do
		orig="$name"
		name="${name%"$ext"}"
		[[ $name != "$orig" ]] && break
	done
	name="${name%.*}"
	extract_with_progress "$parent/$name"
fi
