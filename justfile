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

# Run linter (statix, deadnix, treefmt, actionlint, shellcheck)
lint:
    nix run .#lint

# Format all files
fmt:
    nix run .#fmt

# Re-encrypt all secrets with current .sops.yaml recipients
update-sops-keys:
    bash ./scripts/update-sops-keys.sh

# Update GitHub avatar hash in flake metadata
update-avatar:
    bash ./scripts/update-avatar.sh

# Rotate the encrypted GPG backup gist from the current local key
rotate-gpg-gist:
    nix run .#rotate-gpg-gist

# Show the GPG gist rotation actions without writing to GitHub
rotate-gpg-gist-dry:
    nix run .#rotate-gpg-gist -- --dry-run
