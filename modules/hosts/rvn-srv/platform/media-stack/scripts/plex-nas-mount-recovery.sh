#!/usr/bin/env bash

set -euo pipefail

# Plex NAS mount recovery flow:
#
#   timer or recover-plex-mounts
#                │
#                v
#   plex-nas-mount-recovery.service
#                │
#                v
#      failed mount/automount units?
#          ├─ no ──> stop
#          └─ yes
#              │
#              v
#      attempted within five minutes?
#          ├─ yes ─> skip
#          └─ no
#              │
#              v
#         rvn-nas:445 reachable?
#          ├─ no ──> skip
#          └─ yes
#              │
#              v
#   stamp attempt ─> reset failures ─> start automounts
#                ─> start mounts ─> report status

mount_units=(
  "mnt-nas-video.mount"
  "mnt-nas-LaCie.mount"
)
automount_units=(
  "mnt-nas-video.automount"
  "mnt-nas-LaCie.automount"
)
units=("${mount_units[@]}" "${automount_units[@]}")
failed=()

for unit in "${units[@]}"; do
  result=$(systemctl show --property=Result --value "$unit")
  if systemctl is-failed --quiet "$unit" || [ "$result" != success ]; then
    failed+=("$unit")
  fi
done

if [ "${#failed[@]}" -eq 0 ]; then
  echo "No failed Plex NAS mount units."
  exit 0
fi

stamp=/run/plex-nas-mount-recovery.last
now=$(date +%s)
if [ -e "$stamp" ]; then
  last=$(stat -c %Y "$stamp")
  elapsed=$((now - last))
  if [ "$elapsed" -lt 300 ]; then
    echo "Skipping Plex NAS mount recovery; last attempt was ${elapsed}s ago."
    exit 0
  fi
fi

if ! bash -c 'exec 3<>/dev/tcp/rvn-nas/445' 2>/dev/null; then
  echo "Skipping Plex NAS mount recovery; rvn-nas:445 is unreachable."
  exit 0
fi

touch "$stamp"
echo "Recovering failed Plex NAS units: ${failed[*]}"
systemctl reset-failed "${failed[@]}"
systemctl start "${automount_units[@]}"

for unit in "${mount_units[@]}"; do
  systemctl start "$unit"
done

systemctl --no-pager --full status "${units[@]}" || true
