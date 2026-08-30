#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
installer="$repo_root/scripts/bootstrap/install.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

help_output="$(bash "$installer" --help)"
[[ $help_output == *"Resume a failed encrypted ISO installation"* ]]
[[ $help_output != *"restore"* ]]
[[ $help_output != *"backup-id"* ]]

if grep -Eq 'nvme-WDS|/dev/rvnpc|cryptsystem|48 GiB|rvn-pc now requires' "$installer"; then
  printf 'regular installer contains host-specific encrypted layout values\n' >&2
  exit 1
fi
if grep -Eq 'local-host-recovery|recovery-id|restore_backup' "$installer"; then
  printf 'regular installer depends on recovery backup restoration\n' >&2
  exit 1
fi

export BOOTSTRAP_INSTALL_LIB_ONLY=true
# shellcheck disable=SC1090
source "$installer"

# The sourced installer owns these globals; explicit declarations keep this
# contract test analyzable when ShellCheck cannot follow the dynamic path.
disko_configuration=""
host_system=""
install_user=""
install_uid=""
install_gid=""
gpg_key_id=""
age_alias=""
target_device=""
luks_device=""
luks_mapping=""
target_system_device=""
target_swap_device=""
sops_files=()

mkdir -p "$tmp_dir/secrets/hosts" "$tmp_dir/secrets"
touch \
  "$tmp_dir/secrets/hosts/rvn-pc.yaml" \
  "$tmp_dir/secrets/common.yaml" \
  "$tmp_dir/secrets/apis.yaml" \
  "$tmp_dir/secrets/development.yaml"

nix() {
  case "$*" in
  *"#meta.hosts --apply"*) printf '%s' rvn-pc ;;
  *"installation.sopsFiles"*)
    printf '%s\n' \
      secrets/hosts/rvn-pc.yaml \
      secrets/common.yaml \
      secrets/apis.yaml \
      secrets/development.yaml
    ;;
  *"#meta.hosts.rvn-pc.system"*) printf '%s' x86_64-linux ;;
  *"#meta.user.username"*) printf '%s' fbb ;;
  *"config.users.users.fbb.uid"*) printf '%s' 1000 ;;
  *"config.users.users.fbb.group"*) printf '%s' users ;;
  *"config.users.groups.users.gid"*) printf '%s' 100 ;;
  *"#meta.user.gpg.fingerprint"*) printf '%s' TEST-FINGERPRINT ;;
  *"#diskoConfigurations.rvn-pc.disko.devices.disk"*)
    printf '%s' /dev/disk/by-id/test-target
    ;;
  *"config.boot.initrd.luks.devices"*"builtins.getAttr"*)
    printf '%s' /dev/disk/by-id/test-target-part2
    ;;
  *"config.boot.initrd.luks.devices"*) printf '%s' test-mapping ;;
  *"config.boot.resumeDevice"*) printf '%s' /dev/testvg/swap ;;
  *"config.fileSystems"*) printf '%s' /dev/testvg/system ;;
  *)
    printf 'unexpected nix invocation: %s\n' "$*" >&2
    return 1
    ;;
  esac
}

mapfile -t discovered_hosts < <(discover_install_hosts "$tmp_dir")
[[ ${discovered_hosts[*]} == rvn-pc ]]
configure_install_host "$tmp_dir" rvn-pc
[[ $disko_configuration == rvn-pc ]]
[[ $host_system == x86_64-linux ]]
[[ $install_user == fbb ]]
[[ $install_uid == 1000 ]]
[[ $install_gid == 100 ]]
[[ $gpg_key_id == TEST-FINGERPRINT ]]
[[ $age_alias == rvn-pc ]]
[[ $target_device == /dev/disk/by-id/test-target ]]
[[ $luks_device == /dev/disk/by-id/test-target-part2 ]]
[[ $luks_mapping == test-mapping ]]
[[ $target_system_device == /dev/testvg/system ]]
[[ $target_swap_device == /dev/testvg/swap ]]
[[ ${#sops_files[@]} == 4 ]]

install_body="$(sed -n '/^run_iso_install() {$/,/^}$/p' "$installer")"
for required_call in generate_identities rotate_sops_recipient verify_encrypted_storage; do
  grep -Fq "$required_call" <<<"$install_body" || {
    printf 'integrated installer is missing %s\n' "$required_call" >&2
    exit 1
  }
done
if grep -Eq 'part3|local-host-recovery|restore' <<<"$install_body"; then
  printf 'integrated encrypted install can reach plaintext or recovery logic\n' >&2
  exit 1
fi
storage_verifier="$(sed -n '/^verify_encrypted_storage() {$/,/^}$/p' "$installer")"
for required_check in 'lvs --noheadings' 'pvs --noheadings' 'pv_count' 'mapper_device'; do
  grep -Fq "$required_check" <<<"$storage_verifier" || {
    printf 'encrypted storage verifier is missing %s\n' "$required_check" >&2
    exit 1
  }
done
if grep -Fq 'lsblk --inverse' <<<"$storage_verifier"; then
  printf 'encrypted storage verifier still relies on ambiguous lsblk ancestry\n' >&2
  exit 1
fi
# Keep the destructive confirmation practical to type from the ISO console.
# shellcheck disable=SC2016
grep -Fq 'ERASE $host' <<<"$install_body"

printf 'integrated encrypted installer contract check passed\n'
