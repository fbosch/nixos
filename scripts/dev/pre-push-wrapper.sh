#!/usr/bin/env bash
set -euo pipefail

# Compatibility entry point for hooks installed before the .githooks migration.
repo_root=$(git rev-parse --show-toplevel)
exec "$repo_root/.githooks/pre-push" "$@"
