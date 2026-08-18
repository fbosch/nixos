#!/usr/bin/env bash
# Shared output helpers for diagnostic scripts.
# Source this file: . "$(dirname "$0")/lib/output.sh"

if [ -t 1 ]; then
  BOLD=$'\033[1m'
  CYAN=$'\033[36m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'
else
  BOLD=""
  CYAN=""
  GREEN=""
  YELLOW=""
  RED=""
  DIM=""
  RESET=""
fi

ok() {
  printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$1"
}

fail() {
  printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$1"
}

info() {
  printf '%s[INFO]%s %s\n' "$YELLOW" "$RESET" "$1"
}

section() {
  printf '\n%s%s== %s ==%s\n' "$BOLD$CYAN" "$RESET" "$1" "$RESET"
}

hint() {
  printf '%s       %s%s\n' "$DIM" "$1" "$RESET"
}
