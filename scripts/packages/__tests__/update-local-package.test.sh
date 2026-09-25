#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$repo_root/scripts/packages/update-local-package.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin" "$mock_bin/store/bin"

cat >"$mock_bin/nix" <<'MOCK_NIX'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  build)
    printf 'build\n' >>"$MOCK_NIX_LOG"
    printf '%s\n' "$MOCK_NIX_UPDATE_BIN"
    ;;
  run)
    printf 'run\n' >>"$MOCK_NIX_LOG"
    exit 90
    ;;
  eval)
    printf 'eval\n' >>"$MOCK_NIX_LOG"
    exit 0
    ;;
  *)
    printf 'unexpected nix command: %s\n' "$*" >&2
    exit 91
    ;;
esac
MOCK_NIX

cat >"$mock_bin/store/bin/nix-update" <<'MOCK_UPDATE'
#!/usr/bin/env bash
set -euo pipefail
package="${!#}"
printf '%s\n' "$package" >>"$MOCK_UPDATE_LOG"
if [[ "$package" == filterway ]]; then
  if [[ "$MOCK_UPDATE_FAILURE" == undiscoverable ]]; then
    printf '%s\n' 'nix_update.errors.VersionError: Please specify the version. We can only get the latest version from supported projects.' >&2
  else
    printf '%s\n' 'RuntimeError: upstream is unavailable' >&2
  fi
  exit 1
fi
MOCK_UPDATE

cat >"$mock_bin/gum" <<'MOCK_GUM'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == style ]]; then
  printf '%s' "${!#}"
  exit
fi
exit 0
MOCK_GUM

chmod +x "$mock_bin/nix" "$mock_bin/store/bin/nix-update" "$mock_bin/gum"

run_scan() {
  local failure="$1"
  local output="$2"
  : >"$tmp_dir/nix.log"
  : >"$tmp_dir/update.log"
  MOCK_NIX_LOG="$tmp_dir/nix.log" \
    MOCK_NIX_UPDATE_BIN="$mock_bin/store" \
    MOCK_UPDATE_LOG="$tmp_dir/update.log" \
    MOCK_UPDATE_FAILURE="$failure" \
    PATH="$mock_bin:$PATH" \
    bash "$script" >"$output" 2>&1
}

# Unsupported version discovery is a visible skip, not a traceback or failed scan.
if ! run_scan undiscoverable "$tmp_dir/unsupported.out"; then
  cat "$tmp_dir/unsupported.out" >&2
  exit 1
fi
grep -Fq 'nix-update could not discover an upstream version for .#filterway; skipping automatic check' "$tmp_dir/unsupported.out"
if grep -Fq 'Traceback' "$tmp_dir/unsupported.out"; then
  printf 'unexpected traceback for unsupported version discovery\n' >&2
  exit 1
fi
[[ "$(grep -c '^build$' "$tmp_dir/nix.log")" -eq 1 ]]
[[ "$(grep -c '^run$' "$tmp_dir/nix.log" || true)" -eq 0 ]]
[[ "$(grep -c '^filterway$' "$tmp_dir/update.log")" -eq 1 ]]

# Other updater errors must remain failures and retain their diagnostic output.
if run_scan network "$tmp_dir/network.out"; then
  printf 'unexpected success for an updater runtime failure\n' >&2
  exit 1
fi
grep -Fq '[CHECK] unable to check .#filterway for updates' "$tmp_dir/network.out"
grep -Fq 'RuntimeError: upstream is unavailable' "$tmp_dir/network.out"
[[ "$(grep -c '^build$' "$tmp_dir/nix.log")" -eq 1 ]]

printf 'update-local-package regression checks passed\n'
