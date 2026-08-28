# NixOS flake task runner
# Usage: just <recipe>
#
# Recipes run in a plain shell so they stay usable when the network is down.
# Recipes needing the flake dev shell opt in with `nix develop -c`.

# List available recipes
default:
    @just --list

# Build the rvn-pc NixOS configuration
[group('build')]
build-pc:
    nh os build .#rvn-pc

# Build the rvn-srv NixOS configuration
[group('build')]
build-srv:
    nh os build .#rvn-srv

# Build custom container images for helium
[group('build')]
build-helium:
    sudo build-helium-images

# Build all custom container images
[group('build')]
build-images: build-helium

# Pre-pull the pinned PriceGhost PostgreSQL image before a server switch
[group('build')]
pull-priceghost-postgres:
    sudo podman pull "$(nix eval --raw --impure --expr 'let flake = builtins.getFlake (toString ./.); in flake.nixosConfigurations.rvn-srv.config.services."priceghost-container".postgresImage')"

# Push a Nix closure to Attic (defaults to current host system)
[group('build')]
push-attic $target='' $jobs='3':
    nix develop -c bash -euo pipefail -c 'if [[ -z $target ]]; then target=".#nixosConfigurations.$(hostname).config.system.build.toplevel"; fi; nix path-info -r "$target" | attic push --jobs "$jobs" --no-closure nix-cache --stdin'

# Validate documented service ports against rvn-srv declarations
[group('checks')]
check-service-ports:
    bash ./scripts/ci/check-service-ports.sh

# Format all files
[group('checks')]
fmt:
    nix run .#fmt -- --no-cache

# Run linter (statix, deadnix, treefmt, actionlint, shellcheck)
[group('checks')]
lint:
    nix run .#lint

# Collect read-only Atticd and SQLite lock diagnostics from rvn-srv's repository clone
[group('diagnostics')]
atticd-diagnose $host='srv':
    ssh -tt -o BatchMode=yes "$host" 'bash ~/nixos/scripts/maintenance/atticd-diagnose.sh'

# Interactively inspect disk usage and reclaim Nix garbage or Trash contents
[group('maintenance')]
cleanup-disk:
    nix develop -c bash ./scripts/maintenance/cleanup-disk.sh

# Download the Parakeet ONNX model used by hyprwhspr-rs
[group('maintenance')]
download-hyprwhspr-parakeet $target='':
    bash ./scripts/desktop/download-hyprwhspr-parakeet-model.sh ${target:+"$target"}

# Rotate the encrypted GPG backup gist from the current local key
[group('maintenance')]
rotate-gpg-gist:
    nix run .#rotate-gpg-gist

# Create an atomic recovery archive using the current host manifest
[group('maintenance')]
backup-recovery:
    sudo bash ./scripts/recovery/local-host-recovery.sh backup

# Validate recovery sources and destination without creating an archive
[group('maintenance')]
check-recovery:
    sudo bash ./scripts/recovery/local-host-recovery.sh check

# List recovery archives for the current host, newest first
[group('maintenance')]
list-recovery:
    sudo bash ./scripts/recovery/local-host-recovery.sh list

# Verify a recovery archive by its backup ID
[group('maintenance')]
verify-recovery $backup_id:
    sudo bash ./scripts/recovery/local-host-recovery.sh verify "$backup_id"

# Verify the newest recovery archive for the current host
[group('maintenance')]
verify-latest-recovery:
    sudo bash ./scripts/recovery/local-host-recovery.sh verify-latest

# Show the GPG gist rotation actions without writing to GitHub
[group('maintenance')]
rotate-gpg-gist-dry:
    nix run .#rotate-gpg-gist -- --dry-run

# Sync SDDM wallpaper from hyprpaper config
[group('maintenance')]
sync-wallpaper $config='' $output='' $monitor='':
    bash ./scripts/desktop/sync-wallpaper.sh "$config" "$output" "$monitor"

# Update GitHub avatar hash in flake metadata
[group('maintenance')]
update-avatar:
    bash ./scripts/maintenance/update-avatar.sh

# Add/update current host age key in .sops.yaml and re-encrypt secrets
[group('maintenance')]
update-host-age-key:
    bash ./scripts/bootstrap/bootstrap-age.sh

# Update a local by-name package (optionally pass a package name)
[group('maintenance')]
update-local-package $package='':
    bash ./scripts/packages/update-local-package.sh ${package:+"$package"}

# Re-encrypt all secrets with current .sops.yaml recipients
[group('maintenance')]
update-sops-keys:
    bash ./scripts/maintenance/update-sops-keys.sh

# Show local DNS resolver and service diagnostics
[group('network')]
dns-status $domain='example.com':
    bash ./scripts/network/dns-status.sh "$domain"

# Show network, DNS, and VPN health diagnostics
[group('network')]
network-status $domain='example.com':
    bash ./scripts/network/network-status.sh "$domain"

# Compare public Cloudflare DNS against the system resolver
[group('network')]
network-recovery-check $domain='example.com':
    bash ./scripts/network/network-recovery-check.sh "$domain"

# Align running Mullvad settings with services.mullvad-vpn.runtimeSettings, then verify DNS
[group('network')]
network-restore-dns $domain='example.com':
    bash ./scripts/network/network-restore-dns.sh "$domain"

# Restart local DNS services (Mullvad-aware), then verify public and system DNS
[group('network')]
network-restart-dns $domain='example.com':
    sudo bash ./scripts/network/network-recover.sh dns "$domain"

# Restart NetworkManager and local DNS services (Mullvad-aware), then verify connectivity
[group('network')]
network-reset $domain='example.com':
    sudo bash ./scripts/network/network-recover.sh full "$domain"

# Register U2F key for current user (optionally set rp=pam://rvn-pc)
[group('setup')]
setup-u2f $rp='':
    bash ./scripts/maintenance/setup-u2f.sh ${rp:+"$rp"}

# Install flake-managed pre-commit hooks
[group('setup')]
install-hooks:
    bash ./scripts/dev/install-git-hooks.sh
