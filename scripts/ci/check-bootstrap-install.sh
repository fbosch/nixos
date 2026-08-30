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
export BOOTSTRAP_TEST_GPG_LIBEXECDIR="$tmp_dir/gpg-libexec"
export BOOTSTRAP_TEST_GPG_PRESET_ARGS="$tmp_dir/gpg-preset-args"
export BOOTSTRAP_TEST_GPG_PRESET_INPUT="$tmp_dir/gpg-preset-input"
export BOOTSTRAP_TEST_GH_LOG="$tmp_dir/gh.log"
export BOOTSTRAP_TEST_QRENCODE_ARGS="$tmp_dir/qrencode-args"
export BOOTSTRAP_TEST_NIXOS_INSTALL_ARGS="$tmp_dir/nixos-install-args"
export BOOTSTRAP_TEST_DISKO_SKIP_SWAP="$tmp_dir/disko-skip-swap"
export BOOTSTRAP_TEST_SWAPOFF_ARGS="$tmp_dir/swapoff-args"
export BOOTSTRAP_TEST_UMOUNT_ARGS="$tmp_dir/umount-args"
export BOOTSTRAP_TEST_FLAKE_STORE_PATH="$tmp_dir/flake-store-source"
export BOOTSTRAP_TEST_EVALUATED_DISKO_TARGET="/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746"
export BOOTSTRAP_TEST_FINDMNT_ARGS="$tmp_dir/findmnt-args"

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
      printf '%s\n' '--preserve-env=BOOTSTRAP_INSTALL_ISO_RUNTIME,GPG_KEY_GIST_ID,NIXOS_INSTALL_ACTION,NIXOS_INSTALL_DRY_RUN,NIXOS_INSTALL_HOST'
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

install_host="${install_host-}"
target_device="${target_device-}"

export BOOTSTRAP_GPG_LIB_ONLY=true
# shellcheck disable=SC1091
source "$repo_root/scripts/bootstrap/bootstrap-gpg.sh"
unset BOOTSTRAP_GPG_LIB_ONLY

github_device_url="${github_device_url-}"
if [ -z "$github_device_url" ]; then
  printf 'GPG bootstrap source did not define github_device_url\n' >&2
  exit 1
fi

mkdir "$BOOTSTRAP_TEST_GPG_LIBEXECDIR"
cat >"$tmp_dir/bin/gpg" <<'EOF_GPG'
#!/usr/bin/env bash
set -euo pipefail

for argument in "$@"; do
  if [ "$argument" = "--with-keygrip" ]; then
    awk 'BEGIN {
      OFS = ":"
      print "sec", "u", "3072", "1", "ABCDEF", "0", "0", "", "", "", "", "e"
      print "grp", "", "", "", "", "", "", "", "", "ENCRYPTIONKEYGRIP"
    }'
    exit 0
  fi
  if [ "$argument" = "--decrypt" ] && [ "${BOOTSTRAP_TEST_GPG_DECRYPT_FAIL:-false}" = "true" ]; then
    exit 1
  fi
done

exit 0
EOF_GPG
cat >"$tmp_dir/bin/gpgconf" <<'EOF_GPGCONF'
#!/usr/bin/env bash
if [ "$*" = "--list-dirs libexecdir" ]; then
  printf '%s\n' "$BOOTSTRAP_TEST_GPG_LIBEXECDIR"
  exit 0
fi
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_GPGCONF_ARGS"
EOF_GPGCONF
cat >"$BOOTSTRAP_TEST_GPG_LIBEXECDIR/gpg-preset-passphrase" <<'EOF_GPG_PRESET'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"$BOOTSTRAP_TEST_GPG_PRESET_ARGS"
if [ "${1:-}" = "--preset" ]; then
  passphrase=""
  IFS= read -r passphrase || true
  printf '%s' "$passphrase" >"$BOOTSTRAP_TEST_GPG_PRESET_INPUT"
fi
EOF_GPG_PRESET
cat >"$tmp_dir/bin/pinentry-curses" <<'EOF_PINENTRY'
#!/usr/bin/env bash
exit 0
EOF_PINENTRY
cat >"$tmp_dir/bin/qrencode" <<'EOF_QRENCODE'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_QRENCODE_ARGS"
EOF_QRENCODE
cat >"$tmp_dir/bin/tty" <<'EOF_TTY'
#!/usr/bin/env bash
printf '%s\n' /dev/pts/bootstrap-test
EOF_TTY
chmod +x "$tmp_dir/bin/gpg" "$tmp_dir/bin/gpgconf" "$BOOTSTRAP_TEST_GPG_LIBEXECDIR/gpg-preset-passphrase" \
  "$tmp_dir/bin/pinentry-curses" "$tmp_dir/bin/qrencode" "$tmp_dir/bin/tty"

test_gpg_home="$tmp_dir/gpg-home"
mkdir "$test_gpg_home"
GNUPGHOME="$test_gpg_home"
export GNUPGHOME
configure_gpg_for_sops "$GNUPGHOME"
if [ "$GPG_TTY" != "/dev/pts/bootstrap-test" ]; then
  printf 'ISO GPG setup did not bind pinentry to the concrete terminal\n' >&2
  exit 1
fi
if [ "$SOPS_GPG_EXEC" != "$tmp_dir/bin/gpg" ]; then
  printf 'ISO GPG setup did not select the available gpg binary\n' >&2
  exit 1
fi
cat >"$tmp_dir/expected-gpg-agent.conf" <<EOF_EXPECTED_GPG_AGENT
pinentry-program $tmp_dir/bin/pinentry-curses
allow-preset-passphrase
EOF_EXPECTED_GPG_AGENT
diff -u "$tmp_dir/expected-gpg-agent.conf" "$GNUPGHOME/gpg-agent.conf"

preset_gpg_passphrase_for_sops private-key-passphrase
cat >"$tmp_dir/expected-gpg-preset-args" <<'EOF_EXPECTED_GPG_PRESET_ARGS'
--preset
ENCRYPTIONKEYGRIP
EOF_EXPECTED_GPG_PRESET_ARGS
diff -u "$tmp_dir/expected-gpg-preset-args" "$BOOTSTRAP_TEST_GPG_PRESET_ARGS"
grep -Fqx 'private-key-passphrase' "$BOOTSTRAP_TEST_GPG_PRESET_INPUT"

if BOOTSTRAP_TEST_GPG_DECRYPT_FAIL=true preset_gpg_passphrase_for_sops wrong-passphrase >/dev/null 2>&1; then
  printf 'GPG passphrase setup accepted a failed unlock check\n' >&2
  exit 1
fi
cat >"$tmp_dir/expected-gpg-forget-args" <<'EOF_EXPECTED_GPG_FORGET_ARGS'
--forget
ENCRYPTIONKEYGRIP
EOF_EXPECTED_GPG_FORGET_ARGS
diff -u "$tmp_dir/expected-gpg-forget-args" "$BOOTSTRAP_TEST_GPG_PRESET_ARGS"

iso_work_dir="$tmp_dir/failed-iso-work"
mkdir -p "$iso_work_dir"
touch "$GNUPGHOME/S.gpg-agent"
set +e
(
  set -e
  trap cleanup_iso_install EXIT
  false
)
cleanup_status=$?
set -e
if [ "$cleanup_status" -ne 1 ]; then
  printf 'simulated ISO failure exited with %s instead of 1\n' "$cleanup_status" >&2
  exit 1
fi
cat >"$tmp_dir/expected-gpgconf-args" <<'EOF_EXPECTED_GPGCONF_ARGS'
--kill
all
EOF_EXPECTED_GPGCONF_ARGS
diff -u "$tmp_dir/expected-gpgconf-args" "$BOOTSTRAP_TEST_GPGCONF_ARGS"
if [ -e "$iso_work_dir" ]; then
  printf 'failed ISO workspace was not removed\n' >&2
  exit 1
fi
if [ -e "$GNUPGHOME/gpg-agent.conf" ] || [ -e "$GNUPGHOME/S.gpg-agent" ]; then
  printf 'failed ISO GPG runtime files were not removed\n' >&2
  exit 1
fi
export gpg_runtime_configured="false"

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

: >"$BOOTSTRAP_TEST_QRENCODE_ARGS"
TERM=dumb show_github_device_qr
diff -u "$tmp_dir/expected-qrencode-args" "$BOOTSTRAP_TEST_QRENCODE_ARGS"

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

: >"$BOOTSTRAP_TEST_QRENCODE_ARGS"
authenticate_github_cli
diff -u "$tmp_dir/expected-qrencode-args" "$BOOTSTRAP_TEST_QRENCODE_ARGS"
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

install_action="install"
install_dry_run="false"
install_host=""
parse_args resume --host rvn-pc
if [ "$install_action" != "resume" ] || [ "$NIXOS_INSTALL_ACTION" != "resume" ]; then
  printf 'resume action was not preserved for the selected runtime\n' >&2
  exit 1
fi
if [ "$install_host" != "rvn-pc" ]; then
  printf 'resume action did not retain its host argument\n' >&2
  exit 1
fi

set +e
(
  install_action="install"
  install_dry_run="false"
  parse_args resume --dry-run
) >/dev/null 2>&1
resume_dry_run_status=$?
set -e
if [ "$resume_dry_run_status" -ne 2 ]; then
  printf 'resume accepted the destructive install dry-run mode\n' >&2
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

run_as_install_user() {
  "$@"
}

resume_checkout="$tmp_dir/resume-checkout"
mkdir -p "$resume_checkout/secrets/hosts"
printf '%s\n' 'keys:' >"$resume_checkout/.sops.yaml"
for rotated_file in \
  secrets/hosts/rvn-pc.yaml \
  secrets/common.yaml \
  secrets/apis.yaml \
  secrets/development.yaml; do
  printf '%s\n' encrypted >"$resume_checkout/$rotated_file"
done
git -C "$resume_checkout" init --quiet
git -C "$resume_checkout" add .
git -C "$resume_checkout" -c user.name=Test -c user.email=test@example.invalid commit --quiet -m initial
printf '%s\n' '  - &rvn-pc age1testrecipient' >>"$resume_checkout/.sops.yaml"
for rotated_file in \
  secrets/hosts/rvn-pc.yaml \
  secrets/common.yaml \
  secrets/apis.yaml \
  secrets/development.yaml; do
  printf '%s\n' rotated >>"$resume_checkout/$rotated_file"
done
sops_files=(
  secrets/hosts/rvn-pc.yaml
  secrets/common.yaml
  secrets/apis.yaml
  secrets/development.yaml
)
validate_resume_checkout "$resume_checkout"
printf '%s\n' unexpected >"$resume_checkout/unexpected.txt"
if validate_resume_checkout "$resume_checkout" >/dev/null 2>&1; then
  printf 'resume checkout validation accepted an unexpected file\n' >&2
  exit 1
fi
rm "$resume_checkout/unexpected.txt"

cat >"$tmp_dir/bin/age-keygen" <<'EOF_AGE_KEYGEN'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-y" ]; then
  printf '%s\n' age1testrecipient
  exit 0
fi
exit 1
EOF_AGE_KEYGEN
cat >"$tmp_dir/bin/sops" <<'EOF_SOPS'
#!/usr/bin/env bash
exit 0
EOF_SOPS
chmod +x "$tmp_dir/bin/age-keygen" "$tmp_dir/bin/sops"

install_root="$tmp_dir/resume-root"
install_user="fbb"
age_alias="rvn-pc"
mkdir -p \
  "$install_root/persist/etc/ssh" \
  "$install_root/persist/var/lib/sops-nix" \
  "$install_root/persist/home/fbb/.config/sops/age"
printf '%s\n' 0123456789abcdef0123456789abcdef >"$install_root/persist/etc/machine-id"
printf '%s\n' AGE-SECRET-KEY-TEST >"$install_root/persist/var/lib/sops-nix/key.txt"
cp "$install_root/persist/var/lib/sops-nix/key.txt" \
  "$install_root/persist/home/fbb/.config/sops/age/keys.txt"
ssh-keygen -q -t ed25519 -N '' -f "$install_root/persist/etc/ssh/ssh_host_ed25519_key"
ssh-keygen -q -t rsa -b 2048 -N '' -f "$install_root/persist/etc/ssh/ssh_host_rsa_key"
chmod 0444 "$install_root/persist/etc/machine-id"
chmod 0600 \
  "$install_root/persist/var/lib/sops-nix/key.txt" \
  "$install_root/persist/home/fbb/.config/sops/age/keys.txt"
validate_resume_identities "$resume_checkout"
chmod 0644 "$install_root/persist/etc/machine-id"
printf '\n' >>"$install_root/persist/etc/machine-id"
if validate_resume_identities "$resume_checkout" >/dev/null 2>&1; then
  printf 'resume identity validation accepted an extra machine ID newline\n' >&2
  exit 1
fi
printf '%s\n' malformed >"$install_root/persist/etc/machine-id"
if validate_resume_identities "$resume_checkout" >/dev/null 2>&1; then
  printf 'resume identity validation accepted a malformed machine ID\n' >&2
  exit 1
fi
install_root="/mnt/disko-install-root"

export BOOTSTRAP_TEST_NIX_ARGS="$tmp_dir/nix-args"
cat >"$tmp_dir/bin/nix" <<'EOF_NIX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_NIX_ARGS"
printf '%s' "${DISKO_SKIP_SWAP:-}" >"$BOOTSTRAP_TEST_DISKO_SKIP_SWAP"
if [[ " $* " == *" flake metadata --json "* ]]; then
  printf '{"path":"%s"}\n' "$BOOTSTRAP_TEST_FLAKE_STORE_PATH"
fi
if [[ " $* " == *"#diskoConfigurations."* ]]; then
  printf '%s' "$BOOTSTRAP_TEST_EVALUATED_DISKO_TARGET"
fi
EOF_NIX
cat >"$tmp_dir/bin/nixos-install" <<'EOF_NIXOS_INSTALL'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--help" ]; then
  if [ "${BOOTSTRAP_TEST_NIXOS_INSTALL_INCOMPATIBLE:-false}" = "true" ]; then
    printf '%s\n' '--root'
    exit 0
  fi
  printf '%s\n' --root --flake --no-root-password --no-channel-copy --option
  exit 0
fi
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_NIXOS_INSTALL_ARGS"
EOF_NIXOS_INSTALL
cat >"$tmp_dir/bin/swapoff" <<'EOF_SWAPOFF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_SWAPOFF_ARGS"
EOF_SWAPOFF
cat >"$tmp_dir/bin/mountpoint" <<'EOF_MOUNTPOINT'
#!/usr/bin/env bash
exit 0
EOF_MOUNTPOINT
cat >"$tmp_dir/bin/findmnt" <<'EOF_FINDMNT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_FINDMNT_ARGS"
if [ "${BOOTSTRAP_TEST_FINDMNT_FAIL:-false}" = "true" ]; then
  exit 1
fi
if [[ " $* " == *" --source "* ]] && [ "${BOOTSTRAP_TEST_FINDMNT_SOURCE_INACTIVE:-false}" = "true" ]; then
  exit 1
fi
if [[ " $* " == *" SOURCE,TARGET "* ]]; then
  printf 'tmpfs %s\n' "${BOOTSTRAP_TEST_FINDMNT_ROOT:-/}"
  exit 0
fi
printf '%s\n' "${BOOTSTRAP_TEST_FINDMNT_ROOT:-/}"
EOF_FINDMNT
cat >"$tmp_dir/bin/readlink" <<'EOF_READLINK'
#!/usr/bin/env bash
set -euo pipefail
value="${*: -1}"
case "$value" in
*-part1) printf '%s\n' /dev/mock-part1 ;;
*-part2) printf '%s\n' /dev/mock-part2 ;;
*-part3) printf '%s\n' /dev/mock-part3 ;;
*) printf '%s\n' "$value" ;;
esac
EOF_READLINK
cat >"$tmp_dir/bin/umount" <<'EOF_UMOUNT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_UMOUNT_ARGS"
EOF_UMOUNT
chmod +x "$tmp_dir/bin/nix" "$tmp_dir/bin/nixos-install" "$tmp_dir/bin/swapoff" \
  "$tmp_dir/bin/mountpoint" "$tmp_dir/bin/findmnt" "$tmp_dir/bin/readlink" "$tmp_dir/bin/umount"

mkdir -p "$tmp_dir/repository" "$tmp_dir/identity-tree" "$BOOTSTRAP_TEST_FLAKE_STORE_PATH"
touch "$BOOTSTRAP_TEST_FLAKE_STORE_PATH/flake.nix"
target_device="/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746"
target_swap_device="${target_device}-part2"
resolved_flake="$(resolve_flake_store_path "$tmp_dir/repository")"
if [ "$resolved_flake" != "$BOOTSTRAP_TEST_FLAKE_STORE_PATH" ]; then
  printf 'installation flake did not resolve to the immutable store source\n' >&2
  exit 1
fi
verify_disko_target "$tmp_dir/repository" rvn-pc
if BOOTSTRAP_TEST_EVALUATED_DISKO_TARGET=/dev/disk/by-id/wrong verify_disko_target "$tmp_dir/repository" rvn-pc >/dev/null 2>&1; then
  printf 'installer accepted a Disko target that differs from the displayed disk\n' >&2
  exit 1
fi
run_disko "$tmp_dir/repository" rvn-pc --dry-run
cat >"$tmp_dir/expected-nix-args" <<EOF_EXPECTED_NIX_ARGS
--extra-experimental-features
nix-command flakes
--accept-flake-config
run
$tmp_dir/repository#disko
--
--dry-run
--mode
destroy,format,mount
--flake
$tmp_dir/repository#rvn-pc
--root-mountpoint
/mnt/disko-install-root
EOF_EXPECTED_NIX_ARGS
diff -u "$tmp_dir/expected-nix-args" "$BOOTSTRAP_TEST_NIX_ARGS"
grep -Fqx '1' "$BOOTSTRAP_TEST_DISKO_SKIP_SWAP"

mount_disko "$tmp_dir/repository" rvn-pc
cat >"$tmp_dir/expected-nix-args" <<EOF_EXPECTED_NIX_ARGS
--extra-experimental-features
nix-command flakes
--accept-flake-config
run
$tmp_dir/repository#disko
--
--mode
mount
--flake
$tmp_dir/repository#rvn-pc
--root-mountpoint
/mnt/disko-install-root
EOF_EXPECTED_NIX_ARGS
diff -u "$tmp_dir/expected-nix-args" "$BOOTSTRAP_TEST_NIX_ARGS"
grep -Fqx '1' "$BOOTSTRAP_TEST_DISKO_SKIP_SWAP"
if grep -Eq 'destroy|format' "$BOOTSTRAP_TEST_NIX_ARGS"; then
  printf 'resume Disko invocation included a destructive mode\n' >&2
  exit 1
fi

resume_body="$(sed -n '/^run_iso_resume() {$/,/^}$/p' "$repo_root/scripts/bootstrap/install.sh")"
# This assertion deliberately matches literal shell variables.
# shellcheck disable=SC2016
if ! grep -Fq 'mount_disko "$repository_flake" "$host"' <<<"$resume_body"; then
  printf 'resume orchestration did not invoke the mount-only Disko helper\n' >&2
  exit 1
fi
if grep -Eq 'run_disko|destroy,format|yes-wipe-all-disks' <<<"$resume_body"; then
  printf 'resume orchestration can reach a destructive Disko path\n' >&2
  exit 1
fi

run_disko "$tmp_dir/repository" rvn-pc --yes-wipe-all-disks
cat >"$tmp_dir/expected-nix-args" <<EOF_EXPECTED_NIX_ARGS
--extra-experimental-features
nix-command flakes
--accept-flake-config
run
$tmp_dir/repository#disko
--
--yes-wipe-all-disks
--mode
destroy,format,mount
--flake
$tmp_dir/repository#rvn-pc
--root-mountpoint
/mnt/disko-install-root
EOF_EXPECTED_NIX_ARGS
diff -u "$tmp_dir/expected-nix-args" "$BOOTSTRAP_TEST_NIX_ARGS"

install_nixos "$tmp_dir/repository" rvn-pc
cat >"$tmp_dir/expected-nixos-install-args" <<EOF_EXPECTED_NIXOS_INSTALL_ARGS
--root
/mnt/disko-install-root
--flake
$tmp_dir/repository#rvn-pc
--no-root-password
--no-channel-copy
--option
experimental-features
nix-command flakes
--option
accept-flake-config
true
EOF_EXPECTED_NIXOS_INSTALL_ARGS
diff -u "$tmp_dir/expected-nixos-install-args" "$BOOTSTRAP_TEST_NIXOS_INSTALL_ARGS"

verify_nixos_install_interface
if BOOTSTRAP_TEST_NIXOS_INSTALL_INCOMPATIBLE=true verify_nixos_install_interface >/dev/null 2>&1; then
  printf 'installer accepted an incompatible nixos-install interface\n' >&2
  exit 1
fi

BOOTSTRAP_TEST_FINDMNT_ROOT=/nix verify_target_mount \
  /mnt/disko-install-root/nix \
  /dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part3 \
  btrfs \
  /nix
cat >"$tmp_dir/expected-findmnt-args" <<'EOF_EXPECTED_FINDMNT_ARGS'
--noheadings
--source
/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part3
--target
/mnt/disko-install-root/nix
--types
btrfs
--output
FSROOT
EOF_EXPECTED_FINDMNT_ARGS
diff -u "$tmp_dir/expected-findmnt-args" "$BOOTSTRAP_TEST_FINDMNT_ARGS"
if BOOTSTRAP_TEST_FINDMNT_ROOT=/wrong verify_target_mount /mnt/disko-install-root/nix /dev/target btrfs /nix >/dev/null 2>&1; then
  printf 'installer accepted the wrong Btrfs filesystem root\n' >&2
  exit 1
fi

resume_mountinfo_file="$tmp_dir/mountinfo"
resume_swaps_file="$tmp_dir/swaps"
printf '%s\n' '1 0 0:1 / / rw - tmpfs tmpfs rw' >"$resume_mountinfo_file"
printf '%s\n' 'Filename Type Size Used Priority' >"$resume_swaps_file"
lsblk() {
  case "${*: -1}" in
  *-part1) printf '%s\n' 259:1 ;;
  *-part3) printf '%s\n' 259:3 ;;
  *) return 1 ;;
  esac
}
verify_resume_storage_inactive
printf '%s\n' '2 1 0:2 / /mnt/disko-install-root/nix rw - tmpfs tmpfs rw' >"$resume_mountinfo_file"
if verify_resume_storage_inactive >/dev/null 2>&1; then
  printf 'resume storage validation accepted an existing child mount\n' >&2
  exit 1
fi
printf '%s\n' '3 1 259:3 / /mnt/other rw - btrfs /dev/mock-part3 rw' >"$resume_mountinfo_file"
if verify_resume_storage_inactive >/dev/null 2>&1; then
  printf 'resume storage validation accepted a target partition mounted elsewhere\n' >&2
  exit 1
fi
printf '%s\n' '1 0 0:1 / / rw - tmpfs tmpfs rw' >"$resume_mountinfo_file"
printf '%s\n' \
  'Filename Type Size Used Priority' \
  '/dev/mock-part2 partition 50331644 0 -2' >"$resume_swaps_file"
if verify_resume_storage_inactive >/dev/null 2>&1; then
  printf 'resume storage validation accepted pre-existing target swap\n' >&2
  exit 1
fi
resume_mountinfo_file="$tmp_dir/missing-mountinfo"
if verify_resume_storage_inactive >/dev/null 2>&1; then
  printf 'resume storage validation ignored a missing mount inventory\n' >&2
  exit 1
fi
resume_mountinfo_file="/proc/self/mountinfo"
resume_swaps_file="/proc/swaps"
unset -f lsblk

cat >"$tmp_dir/bin/lsblk" <<'EOF_LSBLK'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" NAME,TYPE "* ]]; then
  printf '%s\n' '/dev/sda disk' '/dev/loop0 loop'
  exit 0
fi
if [ "${*: -1}" = "/dev/sda" ]; then
  printf '%s\n' '1.8T'
  exit 0
fi
exit 1
EOF_LSBLK
chmod +x "$tmp_dir/bin/lsblk"
target_device="/dev/disk/by-id/preview-target"
TERM=dumb NO_COLOR=1 print_install_plan rvn-pc 0123456789abcdef 2>"$tmp_dir/install-plan"
grep -Fqx '  Host      rvn-pc' "$tmp_dir/install-plan"
grep -Fqx '  Revision  0123456789abcdef' "$tmp_dir/install-plan"
grep -Fqx '  Target    /dev/disk/by-id/preview-target' "$tmp_dir/install-plan"
grep -Fqx '    Target disk unavailable in dry-run mode.' "$tmp_dir/install-plan"
grep -Fqx '  [CREATE] Part 1    2 GiB, VFAT, mounted at /boot' "$tmp_dir/install-plan"
grep -Fqx '  [CREATE] Part 2    48 GiB, swap and resume device' "$tmp_dir/install-plan"
grep -Fqx '  [KEEP]  /dev/sda  1.8T' "$tmp_dir/install-plan"
grep -Fqx 'Warning  Only the [ERASE] disk above will be modified. [KEEP] disks will not be touched.' "$tmp_dir/install-plan"
if LC_ALL=C grep -q $'\033' "$tmp_dir/install-plan"; then
  printf 'plain installation plan contained ANSI styling\n' >&2
  exit 1
fi

iso_work_dir="$tmp_dir/iso-work"
mkdir "$iso_work_dir"
target_storage_active="true"
target_swap_active="true"
test_target_install_flake="$tmp_dir/target-install-flake"
target_install_flake="$test_target_install_flake"
mkdir "$target_install_flake"
cleanup_iso_install
if [ -e "$iso_work_dir" ]; then
  printf 'ISO credential workspace was not removed\n' >&2
  exit 1
fi
grep -Fqx "$target_swap_device" "$BOOTSTRAP_TEST_SWAPOFF_ARGS"
cat >"$tmp_dir/expected-umount-args" <<EOF_EXPECTED_UMOUNT_ARGS
-R
/mnt/disko-install-root
EOF_EXPECTED_UMOUNT_ARGS
diff -u "$tmp_dir/expected-umount-args" "$BOOTSTRAP_TEST_UMOUNT_ARGS"
if [ "$target_storage_active" != "false" ]; then
  printf 'ISO target storage remained marked active after cleanup\n' >&2
  exit 1
fi
if [ -e "$test_target_install_flake" ] || [ -n "$target_install_flake" ]; then
  printf 'temporary target-backed installation flake was not removed\n' >&2
  exit 1
fi

printf 'bootstrap installer launcher check passed\n'
