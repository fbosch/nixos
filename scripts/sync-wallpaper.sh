#!/usr/bin/env bash
set -euo pipefail

config_path="${1:-$HOME/.config/hypr/hyprpaper.conf}"
output_path="${2:-assets/wallpaper.png}"
monitor_name="${3:-DP-2}"

if [ ! -f "$config_path" ]; then
  printf 'Config not found: %s\n' "$config_path" >&2
  exit 1
fi

wallpaper_path="$(
  python3 - "$config_path" "$monitor_name" <<'PY'
import sys

config_path = sys.argv[1]
target_monitor = sys.argv[2]

wallpapers = []
current = {"monitor": None, "path": None}
inside = False

with open(config_path, "r", encoding="utf-8") as fh:
    for line in fh:
        stripped = line.strip()
        if stripped.startswith("wallpaper") and stripped.endswith("{"):
            inside = True
            current = {"monitor": None, "path": None}
            continue

        if inside and stripped == "}":
            if current["path"]:
                wallpapers.append(current)
            inside = False
            continue

        if inside and "=" in stripped:
            key, value = [part.strip() for part in stripped.split("=", 1)]
            if key == "monitor":
                current["monitor"] = value
            elif key == "path":
                current["path"] = value

selected = None
for item in wallpapers:
    if item.get("monitor") == target_monitor:
        selected = item.get("path")
        break

if not selected and wallpapers:
    selected = wallpapers[0].get("path")

if not selected:
    sys.exit(1)

print(selected)
PY
)"

if [ -z "$wallpaper_path" ]; then
  printf 'No wallpaper path found in %s\n' "$config_path" >&2
  exit 1
fi

if [ "${wallpaper_path#~}" != "$wallpaper_path" ]; then
  wallpaper_path="$HOME${wallpaper_path#~}"
fi

if [ ! -f "$wallpaper_path" ]; then
  printf 'Wallpaper file not found: %s\n' "$wallpaper_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
cp "$wallpaper_path" "$output_path"

printf 'Synced %s -> %s\n' "$wallpaper_path" "$output_path"
