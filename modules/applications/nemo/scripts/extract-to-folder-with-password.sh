#!/usr/bin/env bash
# Nemo action: extract password-protected archive into a folder.
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

prompt_password() {
	zenity --password \
		--title="Archive password required" \
		--text="Enter password for: $(basename "$file")"
}

list_top_entries() {
	local pass="$1"

	if [[ $is_rar == true ]]; then
		unrar lb -p"$pass" "$file" 2>/dev/null |
			awk -F'[\\\\/]' 'NF && $1 != "" { print $1 }' |
			sort -u
		return
	fi

	7z l -slt -p"$pass" "$file" 2>/dev/null |
		awk -F' = ' '
			/^Path = / {
				path_count++
				if (path_count == 1) next
				split($2, parts, "/")
				if (parts[1] != "") roots[parts[1]] = 1
			}
			END {
				for (k in roots) print k
			}
		' |
		sort -u
}

extract_archive() {
	local output_dir="$1"
	local pass="$2"

	if [[ $is_rar == true ]]; then
		unrar x -idq -o+ -p"$pass" "$file" "$output_dir/"
		return
	fi

	7z x -y -p"$pass" "$file" -o"$output_dir"
}

extract_with_progress() {
	local output_dir="$1"
	local pass="$2"
	local errfile="$3"
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
		extract_archive "$output_dir" "$pass" 2>"$errfile"
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

attempt=1
max_attempts=3
archive_base_name="$(basename "$file")"

for ext in .tar.gz .tar.bz2 .tar.xz .tar.zst .tar.lz4; do
	orig="$archive_base_name"
	archive_base_name="${archive_base_name%"$ext"}"
	[[ $archive_base_name != "$orig" ]] && break
done
archive_base_name="${archive_base_name%.*}"

while [[ $attempt -le $max_attempts ]]; do
	password="$(prompt_password)" || exit 1

	if top_entries="$(list_top_entries "$password")"; then
		top_count=$(printf '%s\n' "$top_entries" | awk 'NF { c++ } END { print c + 0 }')
	else
		top_count=0
	fi

	if [[ $top_count -eq 1 ]]; then
		output_dir="$parent"
	else
		output_dir="$parent/$archive_base_name"
	fi

	errfile="$(mktemp)"
	if extract_with_progress "$output_dir" "$password" "$errfile"; then
		rm -f "$errfile"
		unset password
		exit 0
	fi

	err_text="$(<"$errfile")"
	rm -f "$errfile"

	if [[ $err_text == *"Wrong password"* ]] || [[ $err_text == *"Can not open encrypted archive"* ]] || [[ $err_text == *"Incorrect password"* ]]; then
		if [[ $attempt -lt $max_attempts ]]; then
			zenity --error --title="Wrong password" --text="Password failed. Try again."
			attempt=$((attempt + 1))
			continue
		fi
		zenity --error --title="Wrong password" --text="Password failed after 3 attempts."
		unset password
		exit 1
	fi

	zenity --error --title="Extraction failed" --text="7z failed:\n$err_text"
	unset password
	exit 1
done

unset password
