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
export BOOTSTRAP_TEST_SUDO_ARGS="$tmp_dir/sudo-args"
export BOOTSTRAP_TEST_GPGCONF_ARGS="$tmp_dir/gpgconf-args"
export BOOTSTRAP_TEST_GH_LOG="$tmp_dir/gh.log"
export BOOTSTRAP_TEST_QR_LOG="$tmp_dir/qr.log"
export BOOTSTRAP_TEST_QRENCODE_ARGS="$tmp_dir/qrencode-args"

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

cat >"$tmp_dir/bin/sudo" <<'EOF_SUDO'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"$BOOTSTRAP_TEST_SUDO_ARGS"
if [[ ${1:-} == --preserve-env=* ]]; then
  shift
fi
exec "$@"
EOF_SUDO

chmod +x "$tmp_dir/bin/curl" "$tmp_dir/bin/nix-shell" "$tmp_dir/bin/sudo"

run_launcher() {
  local mode="${1:-installed}"
  : >"$BOOTSTRAP_TEST_CURL_ARGS"
  : >"$BOOTSTRAP_TEST_NIX_SHELL_ARGS"
  : >"$BOOTSTRAP_TEST_SCRIPT_PATH"
  : >"$BOOTSTRAP_TEST_SUDO_ARGS"
  if [ "$mode" = "live-iso" ]; then
    printf '%s\n' 'https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap/install.sh' >"$BOOTSTRAP_TEST_EXPECTED_URL"
    BOOTSTRAP_INSTALL_TEST_MODE=live-iso NIXOS_INSTALL_HOST=rvn-pc bash "$repo_root/scripts/bootstrap/install.sh"
    return
  fi

  printf '%s\n' 'https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap/bootstrap-machine.sh' >"$BOOTSTRAP_TEST_EXPECTED_URL"
  bash "$repo_root/scripts/bootstrap/install.sh"
}

assert_launcher_contract() {
  local script_name="$1"
  local privilege="$2"
  shift 2
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
    printf '%s\n' --run "bash \"$downloaded_script\" </dev/tty"
  } >"$tmp_dir/expected-nix-shell-args"
  diff -u "$tmp_dir/expected-nix-shell-args" "$BOOTSTRAP_TEST_NIX_SHELL_ARGS"

  if [ "$privilege" = "root" ]; then
    {
      printf '%s\n' '--preserve-env=BOOTSTRAP_INSTALL_ISO_RUNTIME,GPG_KEY_GIST_ID,NIXOS_INSTALL_DRY_RUN,NIXOS_INSTALL_HOST'
      printf '%s\n' nix-shell
      cat "$BOOTSTRAP_TEST_NIX_SHELL_ARGS"
    } >"$tmp_dir/expected-sudo-args"
    diff -u "$tmp_dir/expected-sudo-args" "$BOOTSTRAP_TEST_SUDO_ARGS"
  elif [ -s "$BOOTSTRAP_TEST_SUDO_ARGS" ]; then
    printf 'installed launcher unexpectedly used sudo\n' >&2
    exit 1
  fi

  if [ -e "$downloaded_script" ]; then
    printf 'temporary bootstrap script was not removed: %s\n' "$downloaded_script" >&2
    exit 1
  fi
}

run_launcher installed
assert_launcher_contract bootstrap-machine.sh user gh git gum openssh qrencode

run_launcher live-iso
assert_launcher_contract install.sh root age gh git gnupg openssh pinentry-curses qrencode sops util-linux

if BOOTSTRAP_TEST_NIX_SHELL_EXIT=19 run_launcher installed; then
  printf 'launcher ignored nix-shell failure\n' >&2
  exit 1
fi
assert_launcher_contract bootstrap-machine.sh user gh git gum openssh qrencode

export BOOTSTRAP_INSTALL_LIB_ONLY=true
# shellcheck disable=SC1091
source "$repo_root/scripts/bootstrap/install.sh"

export BOOTSTRAP_GPG_LIB_ONLY=true
# shellcheck disable=SC1091
source "$repo_root/scripts/bootstrap/bootstrap-gpg.sh"
unset BOOTSTRAP_GPG_LIB_ONLY

cat >"$tmp_dir/bin/gpg" <<'EOF_GPG'
#!/usr/bin/env bash
exit 0
EOF_GPG
cat >"$tmp_dir/bin/gpgconf" <<'EOF_GPGCONF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_GPGCONF_ARGS"
EOF_GPGCONF
cat >"$tmp_dir/bin/pinentry-curses" <<'EOF_PINENTRY'
#!/usr/bin/env bash
exit 0
EOF_PINENTRY
cat >"$tmp_dir/bin/qrencode" <<'EOF_QRENCODE'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_QRENCODE_ARGS"
EOF_QRENCODE
chmod +x "$tmp_dir/bin/gpg" "$tmp_dir/bin/gpgconf" "$tmp_dir/bin/pinentry-curses" "$tmp_dir/bin/qrencode"

test_gpg_home="$tmp_dir/gpg-home"
mkdir "$test_gpg_home"
GNUPGHOME="$test_gpg_home"
export GNUPGHOME
configure_gpg_for_sops "$GNUPGHOME"
if [ "$GPG_TTY" != "/dev/tty" ]; then
  printf 'ISO GPG setup did not bind pinentry to /dev/tty\n' >&2
  exit 1
fi
if [ "$SOPS_GPG_EXEC" != "$tmp_dir/bin/gpg" ]; then
  printf 'ISO GPG setup did not select the available gpg binary\n' >&2
  exit 1
fi
grep -Fqx "pinentry-program $tmp_dir/bin/pinentry-curses" "$GNUPGHOME/gpg-agent.conf"

touch "$GNUPGHOME/S.gpg-agent"
cleanup_gpg_runtime
cat >"$tmp_dir/expected-gpgconf-args" <<'EOF_EXPECTED_GPGCONF_ARGS'
--kill
all
EOF_EXPECTED_GPGCONF_ARGS
diff -u "$tmp_dir/expected-gpgconf-args" "$BOOTSTRAP_TEST_GPGCONF_ARGS"
if [ -e "$GNUPGHOME/gpg-agent.conf" ] || [ -e "$GNUPGHOME/S.gpg-agent" ]; then
  printf 'ISO GPG runtime files were not removed\n' >&2
  exit 1
fi

render_github_device_qr
cat >"$tmp_dir/expected-qrencode-args" <<EOF_EXPECTED_QRENCODE_ARGS
--type=ANSIUTF8
--level=M
--margin=4
--output=-
--
$github_device_url
EOF_EXPECTED_QRENCODE_ARGS
diff -u "$tmp_dir/expected-qrencode-args" "$BOOTSTRAP_TEST_QRENCODE_ARGS"

show_github_device_qr() {
  printf 'called\n' >"$BOOTSTRAP_TEST_QR_LOG"
}
gh() {
  printf '%s\n' "$*" >>"$BOOTSTRAP_TEST_GH_LOG"
  if [ "$1 $2" = "auth status" ]; then
    return 1
  fi
  if [ "$1 $2" = "auth login" ]; then
    [ "${GH_BROWSER:-}" = "true" ] || return 64
    IFS= read -r browser_confirmation || return 64
    [ -z "$browser_confirmation" ] || return 64
    [ "$*" = "auth login --web --scopes gist" ] || return 64
    return
  fi
  return 64
}

authenticate_github_cli
grep -Fqx 'called' "$BOOTSTRAP_TEST_QR_LOG"
grep -Fqx 'auth login --web --scopes gist' "$BOOTSTRAP_TEST_GH_LOG"

parse_args --dry-run
if [ "$install_dry_run" != "true" ] || [ "$NIXOS_INSTALL_DRY_RUN" != "true" ]; then
  printf 'dry-run option was not preserved for the ISO runtime\n' >&2
  exit 1
fi

parse_args --host rvn-pc
if [ "$install_host" != "rvn-pc" ] || [ "$NIXOS_INSTALL_HOST" != "rvn-pc" ]; then
  printf 'host option was not preserved for the selected runtime\n' >&2
  exit 1
fi

set +e
(
  install_dry_run="invalid"
  parse_args
) >/dev/null 2>&1
invalid_dry_run_status=$?
set -e
if [ "$invalid_dry_run_status" -ne 2 ]; then
  printf 'invalid dry-run environment value exited with %s instead of 2\n' "$invalid_dry_run_status" >&2
  exit 1
fi

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

replace_age_recipient "$sops_config" rvn-pc age1newsystem
grep -Fqx '  - &rvn-pc age1newsystem' "$sops_config"
grep -Fqx '  - &fbb-user age1olduser' "$sops_config"
grep -Fqx '      - *rvn-pc' "$sops_config"
grep -Fqx '      - *fbb-user' "$sops_config"

missing_alias_config="$tmp_dir/missing-alias.yaml"
printf '%s\n' 'keys:' '  - &another-host age1oldsystem' >"$missing_alias_config"
if replace_age_recipient "$missing_alias_config" rvn-pc age1newsystem 2>/dev/null; then
  printf 'recipient replacement accepted a missing host alias\n' >&2
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
target_device="/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746"
run_disko_install "$tmp_dir/repository" "$tmp_dir/identity-tree" rvn-pc --dry-run
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

iso_work_dir="$tmp_dir/iso-work"
mkdir "$iso_work_dir"
cleanup_iso_install
if [ -e "$iso_work_dir" ]; then
  printf 'ISO credential workspace was not removed\n' >&2
  exit 1
fi

printf 'bootstrap installer launcher check passed\n'
