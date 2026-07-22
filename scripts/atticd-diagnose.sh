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

section "Sudo authentication"
sudo -v

section "Atticd service"
systemctl show atticd.service \
  --property=ActiveState \
  --property=SubState \
  --property=Result \
  --property=MainPID \
  --property=ExecMainStartTimestamp \
  --no-pager 2>&1 || true

section "Recent database lock errors"
journalctl -u atticd.service --since '-15 min' --grep='database is locked|SQLITE_BUSY' --no-pager 2>&1 || true

section "SQLite database file handles"
sudo -n lsof -nP \
  /var/lib/private/atticd/server.db \
  /var/lib/private/atticd/server.db-wal \
  /var/lib/private/atticd/server.db-shm 2>&1 || true

section "Atticd SQLite locks"
if locks=$(sudo -n lslocks --json --output PID,COMMAND,TYPE,MODE,PATH); then
  if command -v gum >/dev/null && command -v jq >/dev/null; then
    lock_rows=$(jq -r '
      .locks[]
      | select(.path? != null and (.path | startswith("/var/lib/private/atticd/server.db")))
      | [.pid, .command, .type, .mode, .path]
      | @csv
    ' <<<"$locks")

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
sudo -n stat --format='%n %U:%G %a %s bytes %y' /var/lib/private/atticd/server.db* 2>&1 || true

section "Attic services"
systemctl show atticd.service attic-upload.service \
  --property=ActiveState \
  --property=SubState \
  --property=Result \
  --no-pager 2>&1 || true
