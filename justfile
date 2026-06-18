# NixOS flake task runner
# Usage: just <recipe>

# List available recipes
default:
    @just --list

# Build and switch to the current host configuration
switch:
    nh os switch

# Build without switching (dry run)
build:
    nh os test

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

# Recover Plex NAS media mounts after systemd start-limit failures
recover-plex-mounts:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f modules/services/plex.nix
    sudo systemctl start plex-nas-mount-recovery.service
    systemctl status plex-nas-mount-recovery.service --no-pager || true
    for mountpoint in /mnt/nas/video /mnt/nas/LaCie '/var/lib/plex/Plex Media Server/Cache/Transcode'; do
        findmnt --target "$mountpoint"
    done

# Format all files
fmt:
    nix run .#fmt

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

# Update a local by-name package (optionally pass package=surge)
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

# Install the pre-commit hook
install-hooks:
    mkdir -p .git/hooks
    printf '#!/usr/bin/env bash\nexec nix run .#pre-commit-wrapper "$@"\n' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "Installed pre-commit hook"
