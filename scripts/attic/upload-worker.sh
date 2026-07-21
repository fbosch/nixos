#!/usr/bin/env bash
set -eu

attic_cli="@atticClient@/bin/attic"
cache_name="@cacheName@"
endpoint="@endpoint@"
queue_dir="@queueDir@"
token_file="${CREDENTIALS_DIRECTORY:?}/attic-admin-token"

mkdir -p "$XDG_CONFIG_HOME" "$queue_dir"

while ! "$attic_cli" login --set-default rvn "$endpoint" "$(cat "$token_file")" >/dev/null 2>&1; do
  echo "attic upload worker: login failed; retrying in 30 seconds" >&2
  sleep 30
done

shopt -s nullglob

while true; do
  for processing_file in "$queue_dir"/*.processing; do
    mv "$processing_file" "${processing_file%.processing}.paths"
  done

  for queue_file in "$queue_dir"/*.paths; do
    processing_file="${queue_file%.paths}.processing"
    mv "$queue_file" "$processing_file"

    if "$attic_cli" push "$cache_name" --jobs 1 --stdin <"$processing_file"; then
      rm "$processing_file"
    else
      echo "attic upload worker: push failed; retrying in 30 seconds" >&2
      mv "$processing_file" "$queue_file"
      sleep 30
      break
    fi
  done

  sleep 5
done
