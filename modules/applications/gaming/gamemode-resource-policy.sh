#!/usr/bin/env bash
set -euo pipefail

readonly gamemode_destination="com.feralinteractive.GameMode"
readonly gamemode_path="/com/feralinteractive/GameMode"
readonly gamemode_interface="com.feralinteractive.GameMode"
declare -A protected_scopes=()

is_transient_helper() {
  local pid="$1"
  local executable

  executable="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  case "${executable##*/}" in
  collect2 | coreutils | i386-linux-gnu-inspect-library | ld | ld.bfd | objdump | x86_64-linux-gnu-inspect-library)
    return 0
    ;;
  esac

  return 1
}

apply_policy() {
  local pid="$1"
  local cgroup unit

  [[ $pid =~ ^[0-9]+$ ]] || return 0
  is_transient_helper "$pid" && return 0

  cgroup="$(sed -n 's/^0:://p' "/proc/$pid/cgroup" 2>/dev/null || true)"

  # Only mutate transient scopes owned by this user manager; never apply a game
  # policy to a service or to a cgroup outside the current user's hierarchy.
  [[ $cgroup == "/user.slice/user-$(id -u).slice/user@$(id -u).service/"* ]] || return 0
  unit="$(grep -oE '[^/]+\.scope' <<<"$cgroup" | tail -n 1 || true)"
  [[ -n $unit ]] || return 0
  [[ -z ${protected_scopes[$unit]:-} ]] || return 0

  if systemctl --user set-property --runtime -- "$unit" \
    MemoryLow=12G \
    CPUWeight=900 \
    IOWeight=900; then
    protected_scopes["$unit"]=1
    printf 'Protected GameMode scope: %s\n' "$unit"
  fi
}

apply_registered_games() {
  while read -r pid; do
    apply_policy "$pid"
  done < <(
    busctl --user --json=short call \
      "$gamemode_destination" \
      "$gamemode_path" \
      "$gamemode_interface" \
      ListGames |
      jq -r '.data[0][][0]'
  )
}

coproc GAMEMODE_EVENTS {
  busctl --user monitor --json=short \
    --match="type='signal',sender='$gamemode_destination',interface='$gamemode_interface',member='GameRegistered'"
}

apply_registered_games

while read -r event <&"${GAMEMODE_EVENTS[0]}"; do
  pid="$(jq -r 'select(.member == "GameRegistered") | .payload.data[0] // empty' <<<"$event")"
  [[ -z $pid ]] || apply_policy "$pid"
done
