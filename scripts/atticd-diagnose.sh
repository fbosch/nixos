#!/usr/bin/env bash

set -euo pipefail

section() {
  printf '\n== %s ==\n' "$1"
}

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
  /var/lib/atticd/server.db \
  /var/lib/atticd/server.db-wal \
  /var/lib/atticd/server.db-shm 2>&1 || true

section "Kernel file locks"
sudo -n lslocks --json --output PID,COMMAND,TYPE,MODE,PATH 2>&1 || true

section "SQLite database files"
sudo -n stat --format='%n %U:%G %a %s bytes %y' /var/lib/atticd/server.db* 2>&1 || true

section "Attic services"
systemctl show atticd.service attic-upload.service \
  --property=ActiveState \
  --property=SubState \
  --property=Result \
  --no-pager 2>&1 || true
