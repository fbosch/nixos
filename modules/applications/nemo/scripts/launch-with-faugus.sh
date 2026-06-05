#!/usr/bin/env bash
set -euo pipefail

file="${1:-}"
if [[ -z $file ]]; then
	zenity --error \
		--title="Launch with Faugus" \
		--text="No file selected."
	exit 1
fi

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/faugus-launcher/config.ini"
state_file="${XDG_STATE_HOME:-$HOME/.local/state}/faugus-launcher/nemo-launch-with-faugus.tsv"
runner_cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/faugus-launcher/nemo-runners.tsv"
compatibility_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Steam/compatibilitytools.d"

file_key="$(realpath -- "$file" 2>/dev/null || printf '%s' "$file")"

config_value() {
	local key="$1"
	local line value

	if [[ ! -f $config_file ]]; then
		return 0
	fi

	while IFS= read -r line; do
		if [[ $line == "$key="* ]]; then
			value="${line#*=}"
			value="${value%\"}"
			value="${value#\"}"
			printf '%s' "$value"
			return 0
		fi
	done <"$config_file"
}

is_enabled() {
	[[ $(config_value "$1") == "True" ]]
}

remembered_selection() {
	local key selection

	if [[ ! -f $state_file ]]; then
		return 0
	fi

	while IFS=$'\t' read -r key selection; do
		if [[ $key == "$file_key" ]]; then
			printf '%s' "$selection"
			return 0
		fi
	done <"$state_file"
}

remember_selection() {
	local selected="$1"
	local line state_dir tmp_file

	state_dir="$(dirname "$state_file")"
	mkdir -p "$state_dir"
	tmp_file="$(mktemp "$state_dir/.nemo-launch-with-faugus.XXXXXX")"

	if [[ -f $state_file ]]; then
		while IFS= read -r line; do
			[[ $line == "$file_key"$'\t'* ]] && continue
			printf '%s\n' "$line"
		done <"$state_file" >"$tmp_file"
	fi

	printf '%s\t%s\n' "$file_key" "$selected" >>"$tmp_file"
	mv "$tmp_file" "$state_file"
}

declare -A seen_options=()
options=()

add_option() {
	local option="$1"

	if [[ -n ${seen_options[$option]+set} ]]; then
		return
	fi

	seen_options[$option]=1
	options+=("$option")
}

compatibility_dir_mtime() {
	if [[ -d $compatibility_dir ]]; then
		stat -c '%Y' "$compatibility_dir"
		return
	fi

	printf 'missing'
}

cache_key() {
	printf '%s\t%s\n' "$compatibility_dir" "$(compatibility_dir_mtime)"
}

refresh_runner_cache() {
	local cache_dir key path runtime tmp_file

	cache_dir="$(dirname "$runner_cache_file")"
	mkdir -p "$cache_dir"
	tmp_file="$(mktemp "$cache_dir/.nemo-runners.XXXXXX")"
	key="$(cache_key)"

	printf '%s\n' "$key" >"$tmp_file"

	if [[ -d $compatibility_dir ]]; then
		for path in "$compatibility_dir"/*; do
			[[ -d $path ]] || continue
			runtime="${path##*/}"
			case "$runtime" in
				UMU-Latest|LegacyRuntime|"Proton-GE Latest"*|"Proton-EM Latest"*)
					continue
					;;
			esac
			printf '%s\n' "$runtime"
		done >>"$tmp_file"
	fi

	mv "$tmp_file" "$runner_cache_file"
}

cached_runners() {
	local current_key cached_key

	current_key="$(cache_key)"
	if [[ -f $runner_cache_file ]]; then
		IFS= read -r cached_key <"$runner_cache_file" || cached_key=""
		if [[ $cached_key != "$current_key" ]]; then
			refresh_runner_cache
		fi
	else
		refresh_runner_cache
	fi

	while IFS= read -r runtime; do
		add_option "$runtime"
	done < <(tail -n +2 "$runner_cache_file")
}

default_prefix="$(config_value default-prefix)"
default_runner="$(config_value default-runner)"

if [[ -z $default_prefix ]]; then
	default_prefix="$HOME/Faugus"
fi

selected_default="$default_runner"
if [[ -z $selected_default ]]; then
	selected_default="UMU-Proton Latest"
elif [[ $selected_default == "Proton-GE Latest" ]]; then
	selected_default="GE-Proton Latest (default)"
fi

add_option "GE-Proton Latest (default)"
add_option "UMU-Proton Latest"
add_option "Proton-EM Latest"

if [[ -d /usr/share/steam/compatibilitytools.d/proton-cachyos-slr ]] || [[ -d $HOME/.local/share/Steam/compatibilitytools.d/proton-cachyos-slr ]]; then
	add_option "Proton-CachyOS"
fi

cached_runners

saved_selection="$(remembered_selection)"
has_saved_selection=false
for option in "${options[@]}"; do
	if [[ $option == "$saved_selection" ]]; then
		has_saved_selection=true
		break
	fi
done

if [[ $has_saved_selection == false ]]; then
	for option in "${options[@]}"; do
		if [[ $option == "$selected_default" ]]; then
			saved_selection="$selected_default"
			has_saved_selection=true
			break
		fi
	done
fi

selected="$(
	for option in "${options[@]}"; do
		if { [[ $has_saved_selection == true ]] && [[ $option == "$saved_selection" ]]; } || { [[ $has_saved_selection == false ]] && [[ $option == "${options[0]}" ]]; }; then
			printf 'TRUE\n%s\n' "$option"
		else
			printf 'FALSE\n%s\n' "$option"
		fi
	done | zenity --list \
		--radiolist \
		--title="Launch with Faugus" \
		--text="Select Proton runtime for: $(basename "$file")" \
		--column="" \
		--column="Proton runtime" \
		--height=420 \
		--width=560
)" || exit 0

if [[ -z $selected ]]; then
	exit 0
fi

remember_selection "$selected"

runner="$selected"
case "$selected" in
	"GE-Proton Latest (default)")
		runner="Proton-GE Latest"
		;;
	"UMU-Proton Latest")
		runner=""
		;;
esac

command_parts=(
	"WINEPREFIX=$default_prefix/default"
	"GAMEID=default"
)

if [[ -n $runner ]]; then
	command_parts+=("PROTONPATH=$runner")
fi

if is_enabled disable-hidraw; then
	command_parts+=("PROTON_DISABLE_HIDRAW=1")
fi

if is_enabled prevent-sleep; then
	command_parts+=("PREVENT_SLEEP=1")
fi

if is_enabled gamemode; then
	command_parts+=("gamemoderun")
fi

if is_enabled mangohud; then
	command_parts+=("mangohud")
fi

command_parts+=("umu-run" "$file")

printf -v command '%q ' "${command_parts[@]}"
(cd "$(dirname "$file")" && faugus-run "$command")
