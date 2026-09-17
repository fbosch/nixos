#!/usr/bin/env bash
set -euo pipefail

selection="${1:-}"

if [[ -z $selection ]]; then
  zenity --error \
    --title="Decrypt RPG Maker Game" \
    --text="No game folder or archive was selected." \
    2>/dev/null || true
  exit 1
fi

if [[ -d $selection ]]; then
  game_dir="${selection%/}"
elif [[ -f $selection ]]; then
  case "${selection,,}" in
  *.rgssad | *.rgss2a | *.rgss3a)
    game_dir="$(dirname -- "$selection")"
    ;;
  *)
    zenity --error \
      --title="Decrypt RPG Maker Game" \
      --text="The selected file is not a supported RPG Maker archive." \
      2>/dev/null || true
    exit 1
    ;;
  esac
else
  zenity --error \
    --title="Decrypt RPG Maker Game" \
    --text="The selected item is unavailable." \
    2>/dev/null || true
  exit 1
fi

output_dir="${game_dir}-decrypted"

if [[ -e $output_dir ]]; then
  zenity --question \
    --title="Decrypt into Existing Folder?" \
    --text="The output folder already exists:\n$output_dir" \
    --ok-label="Decrypt" \
    --cancel-label="Cancel" \
    2>/dev/null || exit 0
fi

log_file="$(mktemp --tmpdir rpgm-decrypt.XXXXXX.log)"
trap 'rm -f -- "$log_file"' EXIT

if rpgm-decrypt "$game_dir" "$output_dir" 2>&1 |
  tee "$log_file" |
  zenity --progress \
    --pulsate \
    --auto-close \
    --no-cancel \
    --title="Decrypt RPG Maker Game" \
    --text="Decrypting game…" \
    2>/dev/null; then
  zenity --info \
    --title="Decryption Complete" \
    --text="The decrypted game is in:\n$output_dir" \
    2>/dev/null || true
else
  cat "$log_file" >&2
  zenity --error \
    --title="Unable to Decrypt Game" \
    --text="The RPG Maker game could not be decrypted." \
    2>/dev/null || true
  exit 1
fi
