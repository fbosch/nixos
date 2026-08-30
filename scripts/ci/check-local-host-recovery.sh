#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(realpath -m -- "$(mktemp -d)")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

test_repo="$tmp_dir/repo"
test_script="$test_repo/scripts/recovery/local-host-recovery.sh"
test_manifest="$test_repo/scripts/recovery/manifests/test-host.tsv"
test_destination="$tmp_dir/cifs"
test_source_dir="$tmp_dir/source"
test_secret="recovery-secret-sentinel"

mkdir -p "$test_repo/scripts/recovery/manifests" "$tmp_dir/bin" "$test_destination" "$test_source_dir"
cp "$repo_root/scripts/recovery/local-host-recovery.sh" "$test_script"
printf '%s\n' "$test_secret" >"$test_source_dir/identity key"

write_manifest() {
  local source_path="$1"

  {
    printf 'version\t1\n'
    printf 'destination\t%s\n' "$test_destination"
    printf 'mount-source\t//test-nas/backup\n'
    printf 'source\tfile\t%s\n' "$source_path"
  } >"$test_manifest"
}
write_manifest "$test_source_dir/identity key"

cat >"$tmp_dir/bin/id" <<'EOF_ID'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-u" ]]; then
  printf '0\n'
  exit 0
fi

exit 1
EOF_ID

cat >"$tmp_dir/bin/hostname" <<'EOF_HOSTNAME'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == "-s" ]]
printf '%s\n' "${TEST_HOSTNAME:-test-host}"
EOF_HOSTNAME

cat >"$tmp_dir/bin/findmnt" <<'EOF_FINDMNT'
#!/usr/bin/env bash
set -euo pipefail

output=""
filesystem_filter=""
while (($# > 0)); do
  case "$1" in
  -o)
    output="$2"
    shift 2
    ;;
  -t)
    filesystem_filter="$2"
    shift 2
    ;;
  *) shift ;;
  esac
done

if [[ "$filesystem_filter" != "cifs" ]]; then
  case "$output" in
  SOURCE) printf 'systemd-1\n%s\n' "${TEST_FINDMNT_SOURCE:-//test-nas/backup}" ;;
  TARGET) printf '%s\n%s\n' "$TEST_DESTINATION" "$TEST_DESTINATION" ;;
  *) exit 1 ;;
  esac
  exit 0
fi

case "$output" in
SOURCE) printf '%s\n' "${TEST_FINDMNT_SOURCE:-//test-nas/backup}" ;;
TARGET) printf '%s\n' "$TEST_DESTINATION" ;;
*) exit 1 ;;
esac
EOF_FINDMNT

real_tar="$(command -v tar)"
# GNU tar on Darwin recognizes these flags but exits when archive creation uses them.
if [[ $(uname -s) == Darwin ]]; then
  export REAL_TAR="$real_tar"
  cat >"$tmp_dir/bin/tar" <<'EOF_TAR'
#!/usr/bin/env bash
set -euo pipefail

arguments=()
for argument in "$@"; do
  case "$argument" in
  --acls | --xattrs) ;;
  *) arguments+=("$argument") ;;
  esac
done
exec "$REAL_TAR" "${arguments[@]}"
EOF_TAR
fi

chmod +x "$tmp_dir/bin/"*
export PATH="$tmp_dir/bin:$PATH"
export TEST_DESTINATION="$test_destination"

check_output="$(bash "$test_script" check)"
[[ $check_output == "Recovery check passed: host=test-host sources=1 destination=$test_destination" ]]
[[ ! -e "$test_destination/test-host" ]]
empty_list_output="$(bash "$test_script" list)"
[[ $empty_list_output == "No recovery backups found: host=test-host" ]]
if bash "$test_script" verify-latest >"$tmp_dir/empty-latest.stdout" 2>"$tmp_dir/empty-latest.stderr"; then
  printf 'verify-latest accepted an empty backup directory\n' >&2
  exit 1
fi
[[ ! -s "$tmp_dir/empty-latest.stdout" ]]

backup_output="$(bash "$test_script" backup)"
if [[ $backup_output == *"$test_secret"* ]]; then
  printf 'backup output exposed source contents\n' >&2
  exit 1
fi
backup_id="${backup_output##*id=}"
[[ $backup_id =~ ^[0-9]{8}T[0-9]{6}Z-p[0-9]+$ ]]

backup_dir="$test_destination/test-host/$backup_id"
[[ -f "$backup_dir/payload.tar" ]]
[[ -f "$backup_dir/manifest.tsv" ]]
[[ -f "$backup_dir/SHA256SUMS" ]]
[[ "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type f | wc -l)" == "3" ]]

older_backup_id="20200101T000000Z-p1"
cp -a "$backup_dir" "$test_destination/test-host/$older_backup_id"
mapfile -t list_lines < <(bash "$test_script" list)
[[ ${list_lines[0]} == "Recovery backups: host=test-host" ]]
[[ ${list_lines[1]} == "  $backup_id  "*" ago" ]]
[[ ${list_lines[2]} == "  $older_backup_id  "*" ago" ]]
mapfile -t installer_list_lines < <(TEST_HOSTNAME=nixos bash "$test_script" list --host test-host)
[[ ${installer_list_lines[*]} == "${list_lines[*]}" ]]

verify_output="$(bash "$test_script" verify "$backup_id")"
[[ $verify_output == "Backup verified: host=test-host id=$backup_id" ]]
installer_verify_output="$(TEST_HOSTNAME=nixos bash "$test_script" verify --host test-host "$backup_id")"
[[ $installer_verify_output == "Backup verified: host=test-host id=$backup_id" ]]
latest_verify_output="$(bash "$test_script" verify-latest)"
[[ $latest_verify_output == "Backup verified: host=test-host id=$backup_id" ]]

ln -s /etc/passwd "$tmp_dir/malicious-link"
tar \
  --create \
  --file="$backup_dir/payload.tar" \
  --directory="$tmp_dir" \
  --transform="s|^malicious-link$|${test_source_dir#/}/identity key|" \
  malicious-link
(
  cd "$backup_dir"
  sha256sum payload.tar manifest.tsv >SHA256SUMS
)
if bash "$test_script" verify "$backup_id" >"$tmp_dir/member-type.stdout" 2>"$tmp_dir/member-type.stderr"; then
  printf 'verify accepted a symlink in place of a required file\n' >&2
  exit 1
fi
[[ ! -s "$tmp_dir/member-type.stdout" ]]

if bash "$test_script" verify invalid-id >"$tmp_dir/invalid-id.stdout" 2>"$tmp_dir/invalid-id.stderr"; then
  printf 'verify accepted an invalid backup ID\n' >&2
  exit 1
fi
[[ ! -s "$tmp_dir/invalid-id.stdout" ]]

write_manifest "$test_source_dir/missing"
if bash "$test_script" backup >"$tmp_dir/missing.stdout" 2>"$tmp_dir/missing.stderr"; then
  printf 'backup accepted a missing required source\n' >&2
  exit 1
fi
[[ ! -s "$tmp_dir/missing.stdout" ]]
[[ "$(find "$test_destination/test-host" -mindepth 1 -maxdepth 1 -name '.partial-*' | wc -l)" == "0" ]]
write_manifest "$test_source_dir/identity key"

if TEST_FINDMNT_SOURCE='//wrong/backup' bash "$test_script" backup >"$tmp_dir/mount.stdout" 2>"$tmp_dir/mount.stderr"; then
  printf 'backup accepted an unexpected mount source\n' >&2
  exit 1
fi
[[ ! -s "$tmp_dir/mount.stdout" ]]

printf 'corruption' >>"$backup_dir/payload.tar"
if bash "$test_script" verify "$backup_id" >"$tmp_dir/corrupt.stdout" 2>"$tmp_dir/corrupt.stderr"; then
  printf 'verify accepted a corrupt archive\n' >&2
  exit 1
fi
[[ ! -s "$tmp_dir/corrupt.stdout" ]]

real_mv="$(command -v mv)"
export REAL_MV="$real_mv"
export TEST_MV_DESTINATION="$tmp_dir/mv-destination"
cat >"$tmp_dir/bin/mv" <<'EOF_MV'
#!/usr/bin/env bash
set -euo pipefail

destination=""
has_no_target_directory=false
for argument in "$@"; do
  [[ "$argument" == "--no-target-directory" ]] && has_no_target_directory=true
  destination="$argument"
done
[[ "$has_no_target_directory" == true ]]
printf '%s\n' "$destination" >"$TEST_MV_DESTINATION"
mkdir -- "$destination"
printf 'existing\n' >"$destination/marker"
exec "$REAL_MV" "$@"
EOF_MV
chmod +x "$tmp_dir/bin/mv"

if bash "$test_script" backup >"$tmp_dir/collision.stdout" 2>"$tmp_dir/collision.stderr"; then
  printf 'backup published into a concurrently created destination\n' >&2
  exit 1
fi
[[ ! -s "$tmp_dir/collision.stdout" ]]
collision_destination="$(<"$TEST_MV_DESTINATION")"
[[ -d $collision_destination ]]
[[ -f "$collision_destination/marker" ]]
[[ "$(find "$collision_destination" -mindepth 1 | wc -l)" == "1" ]]
[[ "$(find "$test_destination/test-host" -mindepth 1 -maxdepth 1 -name '.partial-*' | wc -l)" == "0" ]]

help_output="$(bash "$test_script" --help)"
[[ $help_output == *"local-host-recovery.sh backup"* ]]

printf 'local host recovery check passed\n'
