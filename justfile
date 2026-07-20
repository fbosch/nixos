# NixOS flake task runner
# Usage: just <recipe>

# List available recipes
default:
    @just --list

# Run recipes in devenv when the current shell has not already activated it.
set shell := ["bash", "-eu", "-o", "pipefail", "-c", "[ -n \"${DEVENV_ROOT:-}\" ] || exec devenv shell -- bash -eu -o pipefail -c \"$0\"; exec bash -eu -o pipefail -c \"$0\""]

build-pc:
    nh os build .#rvn-pc

build-srv:
    nh os build .#rvn-srv

# Build custom container images for helium
build-helium:
    sudo build-helium-images

# Build custom container images for openmemory
build-openmemory:
    sudo build-openmemory-images

# Build all custom container images
build-images: build-helium build-openmemory

# Push a Nix closure to Attic (defaults to current host system)
push-attic target='' jobs='3':
    if [ -n "{{target}}" ]; then nix path-info -r "{{target}}" | attic push --jobs "{{jobs}}" --no-closure nix-cache --stdin; else nix path-info -r ".#nixosConfigurations.$(hostname).config.system.build.toplevel" | attic push --jobs "{{jobs}}" --no-closure nix-cache --stdin; fi

# Run linter (statix, deadnix, treefmt, actionlint, shellcheck)
lint:
    nix run .#lint

# Validate documented service ports against rvn-srv declarations
check-service-ports:
    bash ./scripts/check-service-ports.sh

# Show local DNS resolver and service diagnostics
dns-status domain='example.com':
    bash ./scripts/dns-status.sh "{{domain}}"

# Show network, DNS, and VPN health diagnostics
network-status domain='example.com':
    bash ./scripts/network-status.sh "{{domain}}"

# Compare public Cloudflare DNS against the system resolver
network-recovery-check domain='example.com':
    bash ./scripts/network-recovery-check.sh "{{domain}}"

# Restart local DNS services, then verify public and system DNS
network-restart-dns domain='example.com':
    sudo bash ./scripts/network-recover.sh dns "{{domain}}"

# Restart NetworkManager and local DNS services, then verify connectivity
network-reset domain='example.com':
    sudo bash ./scripts/network-recover.sh full "{{domain}}"

# Format all files
fmt:
    fmt

# Locate or copy the original package icon for a lazy desktop item
resolve-lazy-icon package desktop_file='' asset_path='':
    bash ./scripts/resolve-lazy-desktop-icon.sh "{{package}}" "{{desktop_file}}" "{{asset_path}}"

# Re-encrypt all secrets with current .sops.yaml recipients
update-sops-keys:
    bash ./scripts/update-sops-keys.sh

# Add/update current host age key in .sops.yaml and re-encrypt secrets
update-host-age-key:
    bash ./scripts/bootstrap-age.sh

# Update GitHub avatar hash in flake metadata
update-avatar:
    bash ./scripts/update-avatar.sh

# Sync SDDM wallpaper from hyprpaper config
sync-wallpaper config="$HOME/.config/hypr/hyprpaper.conf" output="assets/wallpaper.png" monitor="DP-2":
    bash ./scripts/sync-wallpaper.sh "{{config}}" "{{output}}" "{{monitor}}"

# Update a local by-name package (optionally pass surge)
update-local-package package='':
    if [ -n "{{package}}" ]; then bash ./scripts/update-local-package.sh "{{package}}"; else bash ./scripts/update-local-package.sh; fi

# Download the Parakeet ONNX model used by hyprwhspr-rs
download-hyprwhspr-parakeet target="$HOME/.local/share/hyprwhspr-rs/models/parakeet/parakeet-tdt-0.6b-v3-onnx":
    bash ./scripts/download-hyprwhspr-parakeet-model.sh "{{target}}"

# Register U2F key for current user (optionally set rp=pam://rvn-pc)
setup-u2f rp='':
    if [ -n "{{rp}}" ]; then bash ./scripts/setup-u2f.sh "{{rp}}"; else bash ./scripts/setup-u2f.sh; fi

# Rotate the encrypted GPG backup gist from the current local key
rotate-gpg-gist:
    nix run .#rotate-gpg-gist

# Show the GPG gist rotation actions without writing to GitHub
rotate-gpg-gist-dry:
    nix run .#rotate-gpg-gist -- --dry-run

# Install devenv-managed pre-commit hooks
install-hooks:
    devenv shell true
