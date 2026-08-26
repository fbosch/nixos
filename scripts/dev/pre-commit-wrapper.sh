#!/usr/bin/env bash
set -e
repo_root=$(git rev-parse --show-toplevel)
hook_name=$(basename "$0")
exec "$repo_root/scripts/dev/$hook_name-wrapper.sh" "$@"
