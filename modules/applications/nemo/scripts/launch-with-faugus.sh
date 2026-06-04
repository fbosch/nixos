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
compatibility_dirs=(
	"$HOME/.local/share/Steam/compatibilitytools.d"
	"/usr/share/steam/compatibilitytools.d"
)

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

default_prefix="$(config_value default-prefix)"
default_runner="$(config_value default-runner)"

if [[ -z $default_prefix ]]; then
	default_prefix="$HOME/Faugus"
fi

default_runner_label="$default_runner"
if [[ -z $default_runner_label ]]; then
	default_runner_label="UMU-Proton Latest"
elif [[ $default_runner_label == "Proton-GE Latest" ]]; then
	default_runner_label="GE-Proton Latest (default)"
fi

add_option "Faugus default ($default_runner_label)"
add_option "GE-Proton Latest (default)"
add_option "UMU-Proton Latest"
add_option "Proton-EM Latest"

if [[ -d /usr/share/steam/compatibilitytools.d/proton-cachyos-slr ]] || [[ -d $HOME/.local/share/Steam/compatibilitytools.d/proton-cachyos-slr ]]; then
	add_option "Proton-CachyOS"
fi

for compatibility_dir in "${compatibility_dirs[@]}"; do
	[[ -d $compatibility_dir ]] || continue

	while IFS= read -r runtime; do
		add_option "$runtime"
	done < <(
		for path in "$compatibility_dir"/*; do
			[[ -d $path ]] || continue
			runtime="${path##*/}"
			case "$runtime" in
				UMU-Latest|LegacyRuntime|"Proton-GE Latest"*|"Proton-EM Latest"*)
					continue
					;;
			esac
			printf '%s\n' "$runtime"
		done
	)
done

selected="$({ printf '%s\n' "${options[@]}"; } | zenity --list \
	--title="Launch with Faugus" \
	--text="Select Proton runtime for: $(basename "$file")" \
	--column="Proton runtime" \
	--height=420 \
	--width=560)" || exit 0

if [[ -z $selected ]]; then
	exit 0
fi

runner="$selected"
case "$selected" in
	"Faugus default ("*)
		runner="$default_runner"
		;;
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
