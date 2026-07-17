#!/usr/bin/env bash

set -euo pipefail

repo="goodsmileduck/parakeet-tdt-0.6b-v3-onnx"
target_dir="${1:-$HOME/.local/share/hyprwhspr-rs/models/parakeet/parakeet-tdt-0.6b-v3-onnx}"

files=(
  "decoder_joint-model.onnx"
  "encoder-model.onnx"
  "encoder-model.onnx.data"
  "vocab.txt"
)

if ! command -v surge >/dev/null 2>&1; then
  echo "Error: surge is not available in PATH." >&2
  echo "Install it via this flake or run after switching the NixOS config." >&2
  exit 1
fi

mkdir -p "$target_dir"

batch_file="$(mktemp)"
trap 'rm -f "$batch_file"' EXIT

for file in "${files[@]}"; do
  if [ -s "$target_dir/$file" ]; then
    echo "Already present: $target_dir/$file"
    continue
  fi

  printf 'https://huggingface.co/%s/resolve/main/%s\n' "$repo" "$file" >>"$batch_file"
done

if [ -s "$batch_file" ]; then
  echo "Downloading missing Parakeet ONNX files to: $target_dir"
  surge --batch "$batch_file" --output "$target_dir" --exit-when-done
else
  echo "All Parakeet ONNX files are already present."
fi

missing=0
for file in "${files[@]}"; do
  if [ ! -s "$target_dir/$file" ]; then
    echo "Missing after download: $target_dir/$file" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "Parakeet ONNX model ready: $target_dir"
