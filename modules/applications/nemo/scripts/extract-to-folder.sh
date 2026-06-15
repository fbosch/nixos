#!/usr/bin/env bash
set -euo pipefail

password_mode=false
if [[ ${1:-} == "--password" ]]; then
	password_mode=true
	shift
fi

file="$1"
parent="$(dirname "$file")"
file_lower="$(basename "$file" | tr '[:upper:]' '[:lower:]')"

is_rar=false
if [[ $file_lower == *.rar ]]; then
	is_rar=true
fi

archive_base_name="$(basename "$file")"
for ext in .tar.gz .tar.bz2 .tar.xz .tar.zst .tar.lz4; do
	orig="$archive_base_name"
	archive_base_name="${archive_base_name%"$ext"}"
	[[ $archive_base_name != "$orig" ]] && break
done
archive_base_name="${archive_base_name%.*}"

prompt_password() {
	zenity --password \
		--title="Archive password required" \
		--text="Enter password for: $(basename "$file")"
}

password_arg() {
	local pass="${1:-}"

	if [[ $password_mode == true ]]; then
		printf '%s' "-p$pass"
		return
	fi

	printf '%s' "-p-"
}

list_top_entries() {
	local pass="${1:-}"
	local pass_arg
	pass_arg="$(password_arg "$pass")"

	if [[ $is_rar == true ]]; then
		unrar lb "$pass_arg" "$file" 2>/dev/null |
			awk -F'[\\/]' 'NF && $1 != "" { print $1 }' |
			sort -u
		return
	fi

	7zz l -slt "$pass_arg" "$file" 2>/dev/null |
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
	local pass="${2:-}"
	local pass_arg
	pass_arg="$(password_arg "$pass")"

	if [[ $is_rar == true ]]; then
		unrar x -idq -o+ "$pass_arg" "$file" "$output_dir/"
		return
	fi

	7zz x -y "$pass_arg" "$file" -o"$output_dir"
}

extract_with_progress() {
	local output_dir="$1"
	local pass="${2:-}"
	local errfile="$3"
	local status_file
	local cmd_pid
	local status
	local text
	text="Extracting: $(basename "$file")"

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
		--title="Extracting archive" \
		--text="$text" \
		--pulsate \
		--auto-close \
		--no-cancel >/dev/null 2>&1 || true

	wait "$cmd_pid" || true
	read -r status <"$status_file" || status=1
	rm -f "$status_file"
	return "$status"
}

extract_once() {
	local pass="${1:-}"
	local top_entries
	local top_count
	local top_entry
	local output_dir
	local errfile
	local err_text

	if top_entries="$(list_top_entries "$pass")"; then
		top_count=$(printf '%s\n' "$top_entries" | awk 'NF { c++ } END { print c + 0 }')
	else
		top_count=0
	fi

	top_entry="$(printf '%s\n' "$top_entries" | awk 'NF { print; exit }')"

	if [[ $top_count -eq 1 && $top_entry == "$archive_base_name" ]]; then
		output_dir="$parent"
	else
		output_dir="$parent/$archive_base_name"
	fi

	errfile="$(mktemp)"
	if extract_with_progress "$output_dir" "$pass" "$errfile"; then
		rm -f "$errfile"
		return 0
	fi

	err_text="$(<"$errfile")"
	rm -f "$errfile"

	if [[ $err_text == *"Wrong password"* ]] || [[ $err_text == *"Can not open encrypted archive"* ]] || [[ $err_text == *"Incorrect password"* ]]; then
		return 2
	fi

	zenity --error --title="Extraction failed" --text="Extraction failed:\n$err_text"
	return 1
}

if [[ $password_mode == false ]]; then
	if extract_once; then
		exit 0
	else
		status=$?
	fi

	if [[ $status -eq 2 ]]; then
		zenity --error --title="Password required" --text="Archive appears to require a password. Use 'Extract Here (with password)'."
	fi

	exit "$status"
fi

attempt=1
max_attempts=3

while [[ $attempt -le $max_attempts ]]; do
	password="$(prompt_password)" || exit 1

	if extract_once "$password"; then
		unset password
		exit 0
	else
		status=$?
	fi

	if [[ $status -ne 2 ]]; then
		unset password
		exit "$status"
	fi

	if [[ $attempt -lt $max_attempts ]]; then
		zenity --error --title="Wrong password" --text="Password failed. Try again."
		attempt=$((attempt + 1))
		continue
	fi

	zenity --error --title="Wrong password" --text="Password failed after 3 attempts."
	unset password
	exit 1
done
