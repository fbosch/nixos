#!/usr/bin/env bash

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/faugus-launcher/config.json"
requirements_file="${FAUGUS_PREFIX_REQUIREMENTS_FILE:?}"
default_prefix="$HOME/Faugus"
wow64_enabled="False"

if [[ -f $config_file ]]; then
  default_prefix="$(jq -r '."default-prefix" // empty' "$config_file")"
  wow64_enabled="$(jq -r '."wow64-enabled" // "False"' "$config_file")"
fi

if [[ -z $default_prefix ]]; then
  default_prefix="$HOME/Faugus"
fi

compatibility_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Steam/compatibilitytools.d"
failed=false

verbs_are_recorded() {
  local prefix="$1"
  shift

  local verb
  for verb in "$@"; do
    if grep -Fxq "$verb" "$prefix/winetricks.log" 2>/dev/null; then
      continue
    fi
    if grep -Fxq "$verb" "$prefix/winetricks.log.forced" 2>/dev/null; then
      continue
    fi

    return 1
  done
}

while IFS=$'\t' read -r selection runner verbs; do
  [[ -n $selection && -n $runner && -n $verbs ]] || continue

  prefix_name="$(
    printf '%s' "$selection" |
      tr '[:upper:]' '[:lower:]' |
      tr -cs '[:alnum:]_.-' '-'
  )"
  prefix_name="${prefix_name#-}"
  prefix_name="${prefix_name%-}"
  prefix="$default_prefix/nemo-shared/$prefix_name"

  if [[ ! -d $prefix ]]; then
    printf 'Skipping %s: prefix does not exist at %s\n' "$selection" "$prefix"
    continue
  fi

  runner_path=""
  for candidate in \
    "$compatibility_dir/$runner" \
    "$HOME/.steam/root/compatibilitytools.d/$runner" \
    "/usr/share/steam/compatibilitytools.d/$runner"; do
    if [[ -f $candidate/proton ]]; then
      runner_path="$(realpath "$candidate")"
      break
    fi
  done

  if [[ -z $runner_path ]]; then
    printf 'Cannot configure %s: runner %s is not installed.\n' "$selection" "$runner" >&2
    failed=true
    continue
  fi

  read -r -a declared_verbs <<<"$verbs"
  mapfile -t verb_args < <(printf '%s\n' "${declared_verbs[@]}" | sort -u)
  verbs="${verb_args[*]}"

  runner_digest="$(sha256sum "$runner_path/proton" | cut -d ' ' -f 1)"
  requirements_digest="$(
    printf '%s\0%s' "$runner_digest" "$verbs" |
      sha256sum |
      cut -d ' ' -f 1
  )"
  receipt_dir="$prefix/.nix-faugus-prerequisites"
  receipt="$receipt_dir/$requirements_digest"
  mkdir -p "$receipt_dir"

  if ! (
    flock 9

    if [[ -f $receipt ]]; then
      printf '%s is already configured.\n' "$selection"
      exit 0
    fi

    if verbs_are_recorded "$prefix" "${verb_args[@]}"; then
      printf 'Recording existing requirements for %s.\n' "$selection"
    else
      umu_environment=(
        env
        "WINEPREFIX=$prefix"
        "GAMEID=0"
        "STORE=none"
        "PROTONPATH=$runner"
      )
      if [[ $wow64_enabled == "True" ]]; then
        umu_environment+=("PROTON_USE_WOW64=1")
      fi

      printf 'Configuring %s with %s...\n' "$selection" "$verbs"
      if ! "${umu_environment[@]}" umu-run winetricks "${verb_args[@]}"; then
        printf 'Failed to configure %s.\n' "$selection" >&2
        exit 1
      fi
    fi

    if ! verbs_are_recorded "$prefix" "${verb_args[@]}"; then
      printf 'Winetricks did not record all requirements for %s.\n' "$selection" >&2
      exit 1
    fi

    printf 'runner=%s\nrunner-digest=%s\nverbs=%s\n' \
      "$runner_path" "$runner_digest" "$verbs" >"$receipt"
    printf '%s configured successfully.\n' "$selection"
  ) 9>"$receipt_dir/.lock"; then
    failed=true
  fi
done <"$requirements_file"

if [[ $failed == true ]]; then
  exit 1
fi
