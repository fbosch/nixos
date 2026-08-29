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
export BOOTSTRAP_TEST_EXPECTED_URL="$tmp_dir/expected-url"

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

if [ "$url" != "$(cat "$BOOTSTRAP_TEST_EXPECTED_URL")" ]; then
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
  local mode="${1:-installed}"
  : >"$BOOTSTRAP_TEST_CURL_ARGS"
  : >"$BOOTSTRAP_TEST_NIX_SHELL_ARGS"
  : >"$BOOTSTRAP_TEST_SCRIPT_PATH"
  if [ "$mode" = "live-iso" ]; then
    printf '%s\n' 'https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap/install-rvn-pc.sh' >"$BOOTSTRAP_TEST_EXPECTED_URL"
    BOOTSTRAP_INSTALL_TEST_MODE=live-iso NIXOS_INSTALL_HOST=rvn-pc bash "$repo_root/scripts/bootstrap/install.sh"
    return
  fi

  printf '%s\n' 'https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap/bootstrap-machine.sh' >"$BOOTSTRAP_TEST_EXPECTED_URL"
  bash "$repo_root/scripts/bootstrap/install.sh"
}

assert_launcher_contract() {
  local script_name="$1"
  shift
  local downloaded_script
  downloaded_script="$(cat "$BOOTSTRAP_TEST_SCRIPT_PATH")"

  cat >"$tmp_dir/expected-curl-args" <<EOF_EXPECTED_CURL_ARGS
-fsSL
https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap/$script_name
-o
$downloaded_script
EOF_EXPECTED_CURL_ARGS
  diff -u "$tmp_dir/expected-curl-args" "$BOOTSTRAP_TEST_CURL_ARGS"

  {
    printf '%s\n' -p
    printf '%s\n' "$@"
    printf '%s\n' --run "bash \"$downloaded_script\" </dev/tty >/dev/tty"
  } >"$tmp_dir/expected-nix-shell-args"
  diff -u "$tmp_dir/expected-nix-shell-args" "$BOOTSTRAP_TEST_NIX_SHELL_ARGS"

  if [ -e "$downloaded_script" ]; then
    printf 'temporary bootstrap script was not removed: %s\n' "$downloaded_script" >&2
    exit 1
  fi
}

run_launcher installed
assert_launcher_contract bootstrap-machine.sh gh git gum openssh qrencode

run_launcher live-iso
assert_launcher_contract install-rvn-pc.sh age gh git gnupg openssh sops util-linux

if BOOTSTRAP_TEST_NIX_SHELL_EXIT=19 run_launcher installed; then
  printf 'launcher ignored nix-shell failure\n' >&2
  exit 1
fi
assert_launcher_contract bootstrap-machine.sh gh git gum openssh qrencode

export RVN_PC_INSTALL_LIB_ONLY=true
# shellcheck disable=SC1091
source "$repo_root/scripts/bootstrap/install-rvn-pc.sh"

sops_config="$tmp_dir/sops.yaml"
cat >"$sops_config" <<'EOF_SOPS'
keys:
  - &rvn-pc age1oldsystem
  - &admin ABCDEF
  - &fbb-user age1olduser
creation_rules:
  - key_groups:
    - age:
      - *rvn-pc
      - *fbb-user
EOF_SOPS

replace_age_recipients "$sops_config" age1newsystem age1newuser
grep -Fqx '  - &rvn-pc age1newsystem' "$sops_config"
grep -Fqx '  - &fbb-user age1newuser' "$sops_config"
grep -Fqx '      - *rvn-pc' "$sops_config"
grep -Fqx '      - *fbb-user' "$sops_config"

missing_alias_config="$tmp_dir/missing-alias.yaml"
printf '%s\n' 'keys:' '  - &rvn-pc age1oldsystem' >"$missing_alias_config"
if replace_age_recipients "$missing_alias_config" age1newsystem age1newuser; then
  printf 'recipient replacement accepted a missing fbb-user alias\n' >&2
  exit 1
fi

export BOOTSTRAP_TEST_NIX_ARGS="$tmp_dir/nix-args"
cat >"$tmp_dir/bin/nix" <<'EOF_NIX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_NIX_ARGS"
EOF_NIX
chmod +x "$tmp_dir/bin/nix"

mkdir -p "$tmp_dir/repository" "$tmp_dir/identity-tree"
run_disko_install "$tmp_dir/repository" "$tmp_dir/identity-tree" --dry-run
cat >"$tmp_dir/expected-nix-args" <<EOF_EXPECTED_NIX_ARGS
--accept-flake-config
run
$tmp_dir/repository#disko-install
--
--dry-run
--flake
$tmp_dir/repository#rvn-pc
--disk
system
/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746
--mount-point
/mnt/disko-install-root
--write-efi-boot-entries
--extra-files
$tmp_dir/identity-tree/.
persist
EOF_EXPECTED_NIX_ARGS
diff -u "$tmp_dir/expected-nix-args" "$BOOTSTRAP_TEST_NIX_ARGS"

printf 'bootstrap installer launcher check passed\n'
