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
lockfile_path="${LOCKFILE_PATH:?LOCKFILE_PATH is required}"
project_dir="$(dirname "$lockfile_path")"
non_blocking="${PNPM_GLOBALS_NON_BLOCKING:-0}"
managed_current_dir="$state_dir/current"

mkdir -p "$pnpm_home/bin" "$pnpm_store_dir" "$state_dir"

export PNPM_HOME="$pnpm_home"
export PNPM_STORE_DIR="$pnpm_store_dir"
export PATH="$node_bin_dir:$pnpm_bin_dir:$bun_bin_dir:$managed_current_dir/node_modules/.bin:$PATH"

stale_shim_dir="$state_dir/stale-root-shims"
for pnpm_root_entry in "$pnpm_home"/* "$pnpm_home/bin"/*; do
	if [ -e "$pnpm_root_entry" ] && [ ! -d "$pnpm_root_entry" ]; then
		mkdir -p "$stale_shim_dir"
		mv -f "$pnpm_root_entry" "$stale_shim_dir/$(basename "$(dirname "$pnpm_root_entry")")-$(basename "$pnpm_root_entry")"
	fi
done

finish_failed_install() {
	echo ""
	echo "WARNING: Failed to install/update npm global packages." >&2
	if [ "$non_blocking" = 1 ]; then
		echo "Run 'home-manager switch' again to retry." >&2
		exit 0
	fi
	exit 1
}

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

echo "Installing npm global packages from frozen lockfile..."
rm -rf "$managed_current_dir.previous"
if [ -d "$managed_current_dir" ]; then
	mv "$managed_current_dir" "$managed_current_dir.previous"
fi
mkdir -p "$managed_current_dir"
for required_file in package.json pnpm-lock.yaml pnpm-workspace.yaml; do
	if [ ! -f "$project_dir/$required_file" ]; then
		echo "ERROR: $required_file not found in: $project_dir" >&2
		rm -rf "$managed_current_dir"
		if [ -d "$managed_current_dir.previous" ]; then
			mv "$managed_current_dir.previous" "$managed_current_dir"
		fi
		finish_failed_install
	fi
done
cp "$project_dir/package.json" "$project_dir/pnpm-lock.yaml" "$project_dir/pnpm-workspace.yaml" "$managed_current_dir/"

if "$pnpm_bin" --dir "$managed_current_dir" install --frozen-lockfile --prod --ignore-scripts=false 2>&1; then
	for managed_bin in "$managed_current_dir/node_modules/.bin"/*; do
		if [ -e "$managed_bin" ]; then
			wrapper="$pnpm_home/bin/$(basename "$managed_bin")"
			cat > "$wrapper" << EOF
#!/usr/bin/env bash
exec "$managed_bin" "\$@"
EOF
			chmod +x "$wrapper"
		fi
	done
	rm -rf "$managed_current_dir.previous"
	echo ""
	echo "npm global packages are up to date in: $managed_current_dir"
else
	rm -rf "$managed_current_dir"
	if [ -d "$managed_current_dir.previous" ]; then
		mv "$managed_current_dir.previous" "$managed_current_dir"
	fi
	finish_failed_install
fi
