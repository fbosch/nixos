#!/usr/bin/env bash
set -euo pipefail

pnpm_home="${PNPM_HOME_VALUE:?PNPM_HOME_VALUE is required}"
pnpm_store_dir="${PNPM_STORE_DIR_VALUE:?PNPM_STORE_DIR_VALUE is required}"
state_dir="${STATE_DIR_VALUE:-$HOME/.local/state/pnpm-globals}"
npm_registry_host="${NPM_REGISTRY_HOST:-registry.npmjs.org}"
pnpm_bin="${PNPM_BIN:?PNPM_BIN is required}"
node_bin_dir="${NODE_BIN_DIR:?NODE_BIN_DIR is required}"
pnpm_bin_dir="${PNPM_BIN_DIR:?PNPM_BIN_DIR is required}"
bun_bin_dir="${BUN_BIN_DIR:?BUN_BIN_DIR is required}"
latest_packages_file="${LATEST_PACKAGES_FILE:?LATEST_PACKAGES_FILE is required}"
pinned_packages_file="${PINNED_PACKAGES_FILE:?PINNED_PACKAGES_FILE is required}"

mkdir -p "$pnpm_home" "$pnpm_store_dir" "$state_dir"

export PNPM_HOME="$pnpm_home"
export PNPM_STORE_DIR="$pnpm_store_dir"
export PATH="$pnpm_home:$node_bin_dir:$pnpm_bin_dir:$bun_bin_dir:$PATH"

# Only run installs when a new Home Manager generation is activated
# (e.g. via `home-manager switch`), not on every subsequent activation.
if [ -n "${oldGenPath:-}" ] && [ "${oldGenPath}" = "${newGenPath:-}" ]; then
  echo "Home Manager generation unchanged, skipping npm global update"
  exit 0
fi

# Do not block boot/login path. Boot-time Home Manager activation runs
# without a user service manager; defer npm global updates on Linux
# until the user systemd instance is ready.
if command -v systemctl >/dev/null 2>&1 && ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "User systemd daemon not running, skipping npm global update during boot activation"
  exit 0
fi

# Wait for DNS/network before trying npm registry operations.
resolve_host() {
  if command -v getent >/dev/null 2>&1; then
    getent hosts "$1" >/dev/null 2>&1
  elif command -v dscacheutil >/dev/null 2>&1; then
    dscacheutil -q host -a name "$1" >/dev/null 2>&1
  else
    return 0
  fi
}

network_ready=0
for _ in $(seq 1 30); do
  if resolve_host "$npm_registry_host"; then
    network_ready=1
    break
  fi
  sleep 1
done

if [ "$network_ready" -ne 1 ]; then
  echo "WARNING: network not ready for $npm_registry_host, skipping npm global update" >&2
  exit 0
fi

install_failed=0

install_from_file() {
  local package_file="$1"
  local label="$2"
  local -a packages=()
  local package

  while IFS= read -r package || [ -n "$package" ]; do
    if [ -n "$package" ]; then
      packages+=("$package")
    fi
  done < "$package_file"

  if [ "${#packages[@]}" -eq 0 ]; then
    return 0
  fi

  echo "$label"
  if ! "$pnpm_bin" add -g "${packages[@]}" 2>&1; then
    install_failed=1
  fi
}

install_from_file "$latest_packages_file" "Installing/updating @latest npm global packages declared in npm-globals/package.json..."
install_from_file "$pinned_packages_file" "Enforcing pinned npm global package versions declared in npm-globals/package.json..."

if [ "$install_failed" -eq 0 ]; then
  pnpm_global_dir="$($pnpm_bin root -g)"
  echo ""
  echo "npm global packages are up to date in: $pnpm_global_dir"
else
  echo ""
  echo "WARNING: Failed to install/update npm global packages." >&2
  echo "Run 'home-manager switch' again to retry." >&2
fi
