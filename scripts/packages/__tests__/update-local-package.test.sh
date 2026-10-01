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
    if [[ "${2:-}" == --raw && "${3:-}" == --impure ]]; then
      printf '%s\n' 'x86_64-linux'
    elif [[ "${2:-}" == --raw && "${3:-}" == --apply ]]; then
      printf '%s\n' "$MOCK_PACKAGE_NAMES"
    else
      printf 'unexpected nix eval command: %s\n' "$*" >&2
      exit 92
    fi
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
    exit 1
  elif [[ "$MOCK_UPDATE_FAILURE" == network ]]; then
    printf '%s\n' 'RuntimeError: upstream is unavailable' >&2
    exit 1
  fi
fi
if [[ "$package" == font-apple && "$MOCK_UPDATE_FAILURE" == no-src ]]; then
  printf '%s\n' \
    'Traceback (most recent call last):' \
    '  File "update.py", line 78, in fetch_new_version' \
    'nix_update.errors.UpdateError: Could not find a url in the derivations src attribute' >&2
  exit 1
fi

if [[ "$package" == font-fast-font && "$MOCK_UPDATE_MODE" == updated ]]; then
  override_file=""
  while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == --override-filename ]]; then
      override_file="$2"
      shift 2
    else
      shift
    fi
  done
  sed -i 's/version = "final";/version = "new";/' "$override_file"
fi
MOCK_UPDATE

cat >"$mock_bin/gum" <<'MOCK_GUM'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == style ]]; then
  printf '%s' "${!#}"
  exit
fi
if [[ "$1" == choose ]]; then
  cat >>"$MOCK_GUM_CHOOSE_LOG"
  exit 0
fi
exit 0
MOCK_GUM

chmod +x "$mock_bin/nix" "$mock_bin/store/bin/nix-update" "$mock_bin/gum"

run_scan() {
  local failure="$1"
  local output="$2"
  local update_mode="${3:-current}"
  local script_arg="${4:-}"
  local -a script_args=()
  if [[ -n "$script_arg" ]]; then
    script_args=("$script_arg")
  fi
  : >"$tmp_dir/nix.log"
  : >"$tmp_dir/update.log"
  : >"$tmp_dir/choose.log"
  MOCK_NIX_LOG="$tmp_dir/nix.log" \
    MOCK_NIX_UPDATE_BIN="$mock_bin/store" \
    MOCK_UPDATE_LOG="$tmp_dir/update.log" \
    MOCK_UPDATE_FAILURE="$failure" \
    MOCK_UPDATE_MODE="$update_mode" \
    MOCK_GUM_CHOOSE_LOG="$tmp_dir/choose.log" \
    MOCK_PACKAGE_NAMES=$'filterway\nfont-apple\nfont-babelstone-runes\nfont-fast-font\nfont-ionicons\nfont-microsoft\nsurge\nwebapp/apple-maps' \
    PATH="$mock_bin:$PATH" \
    bash "$script" "${script_args[@]}" >"$output" 2>&1
}

# Packages with upstream sources are checked, even if nix-update cannot discover a release.
if run_scan undiscoverable "$tmp_dir/unsupported.out"; then
  printf 'unexpected complete scan for an undiscoverable upstream version\n' >&2
  exit 1
fi
grep -Fq '[CHECK] package .#filterway has an upstream source, but nix-update could not discover its release' "$tmp_dir/unsupported.out"
if grep -Fq '[SKIP] .#filterway' "$tmp_dir/unsupported.out"; then
  printf 'an upstream package was incorrectly skipped\n' >&2
  exit 1
fi
if grep -Fq 'Traceback' "$tmp_dir/unsupported.out"; then
  printf 'unexpected traceback for unsupported version discovery\n' >&2
  exit 1
fi
[[ "$(grep -c '^build$' "$tmp_dir/nix.log")" -eq 1 ]]
[[ "$(grep -c '^run$' "$tmp_dir/nix.log" || true)" -eq 0 ]]
for package in filterway font-apple font-babelstone-runes font-fast-font font-ionicons font-microsoft surge; do
  [[ "$(grep -c "^$package$" "$tmp_dir/update.log")" -eq 1 ]]
done
[[ "$(wc -l <"$tmp_dir/update.log")" -eq 7 ]]
grep -Fq '[CURRENT] .#font-apple is up to date' "$tmp_dir/unsupported.out"
grep -Fq '[CURRENT] .#font-babelstone-runes is up to date' "$tmp_dir/unsupported.out"
grep -Fq '[CURRENT] .#font-fast-font is up to date' "$tmp_dir/unsupported.out"
grep -Fq '[CURRENT] .#font-ionicons is up to date' "$tmp_dir/unsupported.out"
grep -Fq '[CURRENT] .#font-microsoft is up to date' "$tmp_dir/unsupported.out"
grep -Fq '[CURRENT] .#surge is up to date' "$tmp_dir/unsupported.out"
grep -Fq '[SKIP] .#webapp/apple-maps has no upstream package source dependency' "$tmp_dir/unsupported.out"
if run_scan no-src "$tmp_dir/no-src.out"; then
  printf 'unexpected success for an unsupported source expression\n' >&2
  exit 1
fi
grep -Fq '[CHECK] unable to check .#font-apple for updates' "$tmp_dir/no-src.out"
grep -Fq 'nix_update.errors.UpdateError: Could not find a url in the derivations src attribute' "$tmp_dir/no-src.out"
if grep -Fq 'Traceback' "$tmp_dir/no-src.out"; then
  printf 'updater traceback was not filtered\n' >&2
  exit 1
fi

if ! run_scan undiscoverable "$tmp_dir/all.out" current --all; then
  cat "$tmp_dir/all.out" >&2
  exit 1
fi
grep -Fq 'filterway  upstream version not discoverable' "$tmp_dir/choose.log"
grep -Fq 'font-apple  26.2.1' "$tmp_dir/choose.log"
grep -Fq 'font-fast-font  final →' "$tmp_dir/choose.log"
grep -Fq 'font-microsoft  unstable' "$tmp_dir/choose.log"
grep -Fq 'surge  0.12.0' "$tmp_dir/choose.log"
grep -Fq 'webapp/apple-maps  no automatic upstream check' "$tmp_dir/choose.log"


if ! run_scan none "$tmp_dir/updated.out" updated; then
  cat "$tmp_dir/updated.out" >&2
  exit 1
fi
grep -Fq '[UPDATE] .#font-fast-font has an upstream update: final → new' "$tmp_dir/updated.out"
grep -Fq 'font-fast-font  final →' "$tmp_dir/choose.log"
grep -Fq '→ new' "$tmp_dir/choose.log"



# Other updater errors must remain failures and retain their diagnostic output.
if run_scan network "$tmp_dir/network.out"; then
  printf 'unexpected success for an updater runtime failure\n' >&2
  exit 1
fi
grep -Fq '[CHECK] unable to check .#filterway for updates' "$tmp_dir/network.out"
grep -Fq 'RuntimeError: upstream is unavailable' "$tmp_dir/network.out"
[[ "$(grep -c '^build$' "$tmp_dir/nix.log")" -eq 1 ]]

printf 'update-local-package regression checks passed\n'
