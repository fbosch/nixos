#!/usr/bin/env bash

set -euo pipefail

if command -v gum >/dev/null; then
  section() {
    gum style \
      --border rounded \
      --border-foreground 212 \
      --foreground 212 \
      --bold \
      --margin "1 0" \
      --padding "0 1" \
      "$1"
  }
else
  section() {
    printf '\n== %s ==\n' "$1"
  }
fi

status_color() {
  case "$1" in
  active | running | success | healthy)
    printf '%s' 10
    ;;
  activating | deactivating | reloading | starting)
    printf '%s' 214
    ;;
  failed | error | dead | inactive | unhealthy)
    printf '%s' 9
    ;;
  *)
    printf '%s' 7
    ;;
  esac
}

show_service_status() {
  local unit key value

  for unit in "$@"; do
    if command -v gum >/dev/null; then
      gum style --bold --foreground 212 "$unit"
    else
      printf '%s\n' "$unit"
    fi

    while IFS='=' read -r key value; do
      if command -v gum >/dev/null; then
        gum style --foreground "$(status_color "$value")" "${key}=${value}"
      else
        printf '%s=%s\n' "$key" "$value"
      fi
    done < <(
      systemctl show "$unit" \
        --property=ActiveState \
        --property=SubState \
        --property=Result \
        --property=MainPID \
        --property=ExecMainStartTimestamp \
        --no-pager
    )
  done
}

colorize_log() {
  local line

  while IFS= read -r line; do
    if command -v gum >/dev/null && [[ $line == *ERROR* || $line == *error* || $line == *failed* ]]; then
      gum style --foreground 9 "$line"
    else
      printf '%s\n' "$line"
    fi
  done
}

section "Sudo authentication"
sudo -v

section "Atticd service"
show_service_status atticd.service

section "Recent database lock errors"
journalctl -u atticd.service --since '-15 min' --grep='database is locked|SQLITE_BUSY' --no-pager 2>&1 | colorize_log || true

atticd_pid=$(systemctl show --property=MainPID --value atticd.service)
database_path=""
while IFS= read -r field; do
  case "$field" in
  n*server.db)
    database_path="${field#n}"
    break
    ;;
  esac
done < <(sudo -n lsof -nP -p "$atticd_pid" -Fn 2>/dev/null)

section "SQLite database file handles"
if [[ -n $database_path ]]; then
  sudo -n lsof -nP "$database_path" 2>&1 || true
else
  printf 'Atticd has no open SQLite database file.\n'
fi

section "Atticd SQLite locks"
if [[ -z $database_path ]]; then
  printf 'Atticd has no open SQLite database file to inspect.\n'
elif locks=$(sudo -n lslocks --json --output PID,COMMAND,TYPE,MODE,PATH); then
  if command -v gum >/dev/null && command -v jq >/dev/null; then
    lock_rows=$(jq -r '
      .locks[]
      | select(.path? != null and (.path | startswith($database_path)))
      | [.pid, .command, .type, .mode, .path]
      | @csv
    ' --arg database_path "$database_path" <<<"$locks")

    if [[ -n $lock_rows ]]; then
      gum table \
        --print \
        --columns PID,COMMAND,TYPE,MODE,PATH \
        --border rounded \
        --border.foreground 212 \
        --header.foreground 212 \
        <<<"$lock_rows"
    else
      gum style --foreground 212 "No current SQLite locks found."
    fi
  else
    printf '%s\n' "$locks"
  fi
else
  printf 'Unable to inspect kernel file locks.\n' >&2
fi

section "SQLite database files"
if [[ -n $database_path ]]; then
  sudo -n stat --format='%n %U:%G %a %s bytes %y' "$database_path" 2>&1 || true
else
  printf 'Atticd has no open SQLite database file to inspect.\n'
fi

section "Attic services"
show_service_status atticd.service attic-upload.service
