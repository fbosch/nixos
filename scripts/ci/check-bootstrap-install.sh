#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/home" "$tmp_dir/tmp"
export PATH="$tmp_dir/bin:$PATH"
export HOME="$tmp_dir/home"
export TMPDIR="$tmp_dir/tmp"
export BOOTSTRAP_TEST_CURL_ARGS="$tmp_dir/curl-args"
export BOOTSTRAP_TEST_NIX_SHELL_ARGS="$tmp_dir/nix-shell-args"
export BOOTSTRAP_TEST_SCRIPT_PATH="$tmp_dir/script-path"

cat >"$tmp_dir/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"$BOOTSTRAP_TEST_CURL_ARGS"
url=""
output_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  -o)
    output_file="$2"
    shift 2
    ;;
  -*) shift ;;
  *)
    url="$1"
    shift
    ;;
  esac
done

if [ "$url" != "https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap/bootstrap-machine.sh" ]; then
  printf 'unexpected bootstrap URL: %s\n' "$url" >&2
  exit 1
fi

if [ -z "$output_file" ]; then
  printf 'curl was not given an output file\n' >&2
  exit 1
fi

printf '#!/usr/bin/env bash\nexit 0\n' >"$output_file"
printf '%s\n' "$output_file" >"$BOOTSTRAP_TEST_SCRIPT_PATH"
EOF_CURL

cat >"$tmp_dir/bin/nix-shell" <<'EOF_NIX_SHELL'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"$BOOTSTRAP_TEST_NIX_SHELL_ARGS"
downloaded_script="$(cat "$BOOTSTRAP_TEST_SCRIPT_PATH")"
if [ ! -f "$downloaded_script" ]; then
  printf 'downloaded bootstrap script was missing before nix-shell invocation\n' >&2
  exit 1
fi

exit "${BOOTSTRAP_TEST_NIX_SHELL_EXIT:-0}"
EOF_NIX_SHELL

chmod +x "$tmp_dir/bin/curl" "$tmp_dir/bin/nix-shell"

run_launcher() {
  : >"$BOOTSTRAP_TEST_CURL_ARGS"
  : >"$BOOTSTRAP_TEST_NIX_SHELL_ARGS"
  : >"$BOOTSTRAP_TEST_SCRIPT_PATH"
  bash "$repo_root/scripts/bootstrap/install.sh"
}

assert_launcher_contract() {
  local downloaded_script
  downloaded_script="$(cat "$BOOTSTRAP_TEST_SCRIPT_PATH")"

  cat >"$tmp_dir/expected-curl-args" <<EOF_EXPECTED_CURL_ARGS
-fsSL
https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap/bootstrap-machine.sh
-o
$downloaded_script
EOF_EXPECTED_CURL_ARGS
  diff -u "$tmp_dir/expected-curl-args" "$BOOTSTRAP_TEST_CURL_ARGS"

  cat >"$tmp_dir/expected-nix-shell-args" <<EOF_EXPECTED_NIX_SHELL_ARGS
-p
gh
git
gum
openssh
qrencode
--run
bash "$downloaded_script"
EOF_EXPECTED_NIX_SHELL_ARGS
  diff -u "$tmp_dir/expected-nix-shell-args" "$BOOTSTRAP_TEST_NIX_SHELL_ARGS"

  if [ -e "$downloaded_script" ]; then
    printf 'temporary bootstrap script was not removed: %s\n' "$downloaded_script" >&2
    exit 1
  fi
}

run_launcher
assert_launcher_contract

if BOOTSTRAP_TEST_NIX_SHELL_EXIT=19 run_launcher; then
  printf 'launcher ignored nix-shell failure\n' >&2
  exit 1
fi
assert_launcher_contract

printf 'bootstrap installer launcher check passed\n'
