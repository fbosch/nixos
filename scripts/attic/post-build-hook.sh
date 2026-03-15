#!/usr/bin/env bash
set -u

attic_cli="@atticClient@/bin/attic"
token_file="@tokenFile@"
cache_name="@cacheName@"
endpoint="@endpoint@"

if [ -z "${OUT_PATHS:-}" ]; then
  exit 0
fi

if [ ! -r "$token_file" ]; then
  echo "attic post-build hook: token file missing or unreadable: $token_file" >&2
  exit 0
fi

if "$attic_cli" login --set-default rvn "$endpoint" "$(cat "$token_file")" >/dev/null 2>&1; then
  IFS=' ' read -r -a out_paths <<< "${OUT_PATHS}"
  printf '%s\n' "${out_paths[@]}" | "$attic_cli" push "$cache_name" --stdin >/dev/null 2>&1 || \
    echo "attic post-build hook: push failed" >&2
else
  echo "attic post-build hook: login failed" >&2
fi

exit 0
