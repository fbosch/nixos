#!/usr/bin/env bash

set -e

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [ -z "${NIX_PRE_PUSH_HOOK:-}" ]; then
  export NIX_PRE_PUSH_HOOK=1
  exec nix develop --command "$0" "$@"
fi

hook_dir=$(cd "$(dirname "$0")" && pwd)
exec pre-commit hook-impl --config=.pre-commit-config.yaml --hook-type=pre-push --hook-dir "$hook_dir" -- "$@"
