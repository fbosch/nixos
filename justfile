# NixOS flake task runner
# Usage: just <recipe>

hostname := `hostname`

# List available recipes
default:
    @just --list

# Build and switch to the current host configuration
switch:
    sudo nixos-rebuild switch --flake .

# Build without switching (dry run)
build:
    nixos-rebuild build --flake .

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
