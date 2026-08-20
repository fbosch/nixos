#!/usr/bin/env bash
set -euo pipefail

for theme in Vision-Black Vision-White; do
  cursors="$theme/cursors"

  if [[ ! -d "$cursors" ]]; then
    echo "Vision cursor theme is missing $cursors" >&2
    exit 1
  fi

  for required_cursor in pointer link; do
    if [[ ! -e "$cursors/$required_cursor" ]]; then
      echo "Vision cursor theme is missing $cursors/$required_cursor" >&2
      exit 1
    fi
  done

  default_target="$(readlink -f "$cursors/pointer")"
  link_target="$(readlink -f "$cursors/link")"

  if cmp -s "$default_target" "$link_target"; then
    echo "Vision cursor pointer and link assets unexpectedly resolve to the same cursor" >&2
    exit 1
  fi

  # Upstream follows Windows naming, where pointer is the default arrow and
  # link is the hand cursor. Preserve the original arrow before normalizing
  # the Linux/XCursor pointer aliases below.
  cp --dereference "$default_target" "$cursors/.vision-default"
  cp --dereference "$link_target" "$cursors/.vision-pointer"

  # Keep any existing aliases that referred to the original default arrow on
  # the arrow after `pointer` is repurposed to the XCursor hand semantics.
  for cursor in "$cursors"/*; do
    if [[ -L "$cursor" && "$(readlink -f "$cursor")" == "$default_target" ]]; then
      ln -sfn .vision-default "$cursor"
    fi
  done

  for cursor_name in default arrow left_ptr; do
    if [[ ! -e "$cursors/$cursor_name" ]]; then
      ln -s .vision-default "$cursors/$cursor_name"
    fi
  done

  # GTK/X11 applications use several names for the clickable hand cursor.
  # The two hashes are the standard XCursor pointer aliases used by modern
  # cursor themes.
  for cursor_name in \
    pointer \
    hand \
    hand1 \
    hand2 \
    pointing_hand \
    9d800788f1b08800ae810202380a0822 \
    e29285e634086352946a0e7090d73106
  do
    rm -f "$cursors/$cursor_name"
    ln -s .vision-pointer "$cursors/$cursor_name"
  done

  rm -f "$cursors/link"
  ln -s .vision-pointer "$cursors/link"
done
