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
export BOOTSTRAP_TEST_GH_LOG="$tmp_dir/gh.log"
export BOOTSTRAP_TEST_GUM_LOG="$tmp_dir/gum.log"
export BOOTSTRAP_TEST_QR_LOG="$tmp_dir/qr.log"
export BOOTSTRAP_TEST_QRENCODE_ARGS="$tmp_dir/qrencode-args"

cat >"$tmp_dir/bin/bootstrap-test-blocked" <<'EOF_BLOCKED'
#!/usr/bin/env bash
printf 'blocked command escaped bootstrap test isolation: %s\n' "${0##*/}" >&2
exit 97
EOF_BLOCKED
chmod +x "$tmp_dir/bin/bootstrap-test-blocked"

for command_name in gh git gpg gum nix-shell nixos-rebuild reboot ssh-keygen sudo; do
  cp "$tmp_dir/bin/bootstrap-test-blocked" "$tmp_dir/bin/$command_name"
done

export BOOTSTRAP_MACHINE_LIB_ONLY=true
# The source path is resolved dynamically from the repository root.
# shellcheck disable=SC1091
source "$repo_root/scripts/bootstrap/bootstrap-machine.sh"
unset BOOTSTRAP_MACHINE_LIB_ONLY

cat >"$tmp_dir/bin/qrencode" <<'EOF_QRENCODE'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BOOTSTRAP_TEST_QRENCODE_ARGS"
exit "${BOOTSTRAP_TEST_QRENCODE_EXIT:-0}"
EOF_QRENCODE

cat >"$tmp_dir/bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BOOTSTRAP_TEST_GH_LOG"

case "$1 $2" in
"auth status")
  [ "$#" -eq 2 ] || exit 64
  [ "$BOOTSTRAP_TEST_GH_STATE" != "unauthenticated" ]
  ;;
"auth login")
  [ "$#" -eq 8 ] || exit 64
  [ "$3" = "--git-protocol" ] || exit 64
  [ "$4" = "ssh" ] || exit 64
  [ "$5" = "--web" ] || exit 64
  [ "$6" = "--skip-ssh-key" ] || exit 64
  [ "$7" = "--scopes" ] || exit 64
  [ "$8" = "admin:public_key" ] || exit 64
  exit "${BOOTSTRAP_TEST_GH_LOGIN_EXIT:-0}"
  ;;
"auth token")
  [ "$#" -eq 2 ] || exit 64
  ;;
"api user/keys")
  [ "$#" -eq 4 ] || exit 64
  [ "$3" = "--jq" ] || exit 64
  [ "$4" = ".[0].id" ] || exit 64
  [ "${BOOTSTRAP_TEST_GH_API_STATE:-available}" != "missing" ]
  ;;
"auth refresh")
  [ "$#" -eq 6 ] || exit 64
  [ "$3" = "-h" ] || exit 64
  [ "$4" = "github.com" ] || exit 64
  [ "$5" = "-s" ] || exit 64
  [ "$6" = "admin:public_key" ] || exit 64
  exit "${BOOTSTRAP_TEST_GH_REFRESH_EXIT:-0}"
  ;;
*) exit 64 ;;
esac
EOF_GH

chmod +x "$tmp_dir/bin/gh" "$tmp_dir/bin/qrencode"

gum() {
  printf '%s\n' "$*" >>"$BOOTSTRAP_TEST_GUM_LOG"
}

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

: >"$BOOTSTRAP_TEST_GUM_LOG"
export BOOTSTRAP_TEST_QRENCODE_EXIT=1
render_github_device_qr
grep -Fq 'QR rendering failed; open the URL above manually.' "$BOOTSTRAP_TEST_GUM_LOG"
unset BOOTSTRAP_TEST_QRENCODE_EXIT

show_github_device_qr() {
  printf 'called\n' >>"$BOOTSTRAP_TEST_QR_LOG"
}

: >"$BOOTSTRAP_TEST_GH_LOG"
: >"$BOOTSTRAP_TEST_GUM_LOG"
: >"$BOOTSTRAP_TEST_QR_LOG"
export BOOTSTRAP_TEST_GH_STATE=authenticated
authenticate_github_cli
if grep -Fq 'auth login' "$BOOTSTRAP_TEST_GH_LOG"; then
  printf 'authenticated GitHub flow attempted login\n' >&2
  exit 1
fi
if [ -s "$BOOTSTRAP_TEST_QR_LOG" ]; then
  printf 'authenticated GitHub flow attempted QR rendering\n' >&2
  exit 1
fi
grep -Fq 'GitHub CLI already authenticated.' "$BOOTSTRAP_TEST_GUM_LOG"

: >"$BOOTSTRAP_TEST_GH_LOG"
: >"$BOOTSTRAP_TEST_GUM_LOG"
: >"$BOOTSTRAP_TEST_QR_LOG"
export BOOTSTRAP_TEST_GH_STATE=unauthenticated
authenticate_github_cli
grep -Fq 'auth login --git-protocol ssh --web --skip-ssh-key --scopes admin:public_key' "$BOOTSTRAP_TEST_GH_LOG"
grep -Fq 'called' "$BOOTSTRAP_TEST_QR_LOG"

export BOOTSTRAP_TEST_GH_LOGIN_EXIT=23
set +e
(
  set -e
  authenticate_github_cli
)
login_status=$?
set -e
unset BOOTSTRAP_TEST_GH_LOGIN_EXIT
if [ "$login_status" -ne 23 ]; then
  printf 'GitHub login failure was not propagated: %s\n' "$login_status" >&2
  exit 1
fi

export BOOTSTRAP_TEST_GH_STATE=authenticated
export BOOTSTRAP_TEST_GH_API_STATE=missing
export BOOTSTRAP_TEST_GH_REFRESH_EXIT=29
set +e
(
  set -e
  authenticate_github_cli
)
refresh_status=$?
set -e
unset BOOTSTRAP_TEST_GH_API_STATE BOOTSTRAP_TEST_GH_REFRESH_EXIT
if [ "$refresh_status" -ne 29 ]; then
  printf 'GitHub scope refresh failure was not propagated: %s\n' "$refresh_status" >&2
  exit 1
fi

if (validate_name "." "Host name" >/dev/null 2>&1); then
  echo "validate_name accepted ." >&2
  exit 1
fi

if (validate_name ".." "Host name" >/dev/null 2>&1); then
  echo "validate_name accepted .." >&2
  exit 1
fi

cat >"$tmp_dir/configuration-source.nix" <<'EOF_CONFIGURATION'
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "bootstrap-test";
  system.stateVersion = "25.05";
}
EOF_CONFIGURATION

cat >"$tmp_dir/hardware-source.nix" <<'EOF_HARDWARE'
{ lib, ... }:
{
  fileSystems."/" = {
    device = "/dev/bootstrap-test";
    fsType = "ext4";
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
EOF_HARDWARE

render_host_module \
  desktop \
  bootstrap-test \
  desktop \
  x86_64-linux \
  "$tmp_dir/default.nix"
render_wrapped_nixos_module \
  "$tmp_dir/configuration-source.nix" \
  "hosts/bootstrap-test/configuration" \
  "$tmp_dir/configuration.nix" \
  true
render_wrapped_nixos_module \
  "$tmp_dir/hardware-source.nix" \
  "hosts/bootstrap-test/hardware" \
  "$tmp_dir/hardware.nix"

validate_generated_module "$tmp_dir/default.nix"
validate_generated_module "$tmp_dir/configuration.nix"
validate_generated_module "$tmp_dir/hardware.nix"

grep -Fq 'hosts."bootstrap-test"' "$tmp_dir/default.nix"
grep -Fq '"hosts/bootstrap-test/configuration"' "$tmp_dir/default.nix"
grep -Fq '"hosts/bootstrap-test/hardware"' "$tmp_dir/default.nix"
grep -Fq '"presets/desktop"' "$tmp_dir/default.nix"
grep -Fq 'flake.modules.nixos."hosts/bootstrap-test/configuration"' "$tmp_dir/configuration.nix"
grep -Fq 'flake.modules.nixos."hosts/bootstrap-test/hardware"' "$tmp_dir/hardware.nix"

if grep -Fq './hardware-configuration.nix' "$tmp_dir/configuration.nix"; then
  echo "configuration wrapper retained the legacy hardware import" >&2
  exit 1
fi

if grep -Fq 'home-manager.users' "$tmp_dir/default.nix"; then
  echo "host module retained manual Home Manager wiring" >&2
  exit 1
fi

printf 'bootstrap machine check passed\n'
