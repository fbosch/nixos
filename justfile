# NixOS flake task runner
# Usage: just <recipe>

[doc("List available recipes")]
default:
    @just --list

[doc("Build and switch to the current host configuration")]
switch:
    nh os switch

[doc("Build without switching (dry run)")]
build:
    nh os test

[doc("Build custom container images for helium")]
build-helium:
    sudo build-helium-images

[doc("Build custom container images for openmemory")]
build-openmemory:
    sudo build-openmemory-images

[doc("Build all custom container images")]
build-images: build-helium build-openmemory

[doc("Run linter (statix, deadnix, treefmt, actionlint, shellcheck)")]
lint:
    nix run .#lint

[doc("Validate documented service ports against rvn-srv declarations")]
check-service-ports:
    bash ./scripts/check-service-ports.sh

[doc("Format all files")]
fmt:
    nix run .#fmt

[doc("Re-encrypt all secrets with current .sops.yaml recipients")]
update-sops-keys:
    bash ./scripts/update-sops-keys.sh

[doc("Add/update current host age key in .sops.yaml and re-encrypt secrets")]
update-host-age-key:
    bash ./scripts/bootstrap-age.sh

[doc("Update GitHub avatar hash in flake metadata")]
update-avatar:
    bash ./scripts/update-avatar.sh

[doc("Sync SDDM wallpaper from hyprpaper config")]
sync-wallpaper config="$HOME/.config/hypr/hyprpaper.conf" output="assets/wallpaper.png" monitor="DP-2":
    bash ./scripts/sync-wallpaper.sh "{{config}}" "{{output}}" "{{monitor}}"

[doc("Update a local by-name package (optionally pass package=surge)")]
update-local-package package='':
    if [ -n "{{package}}" ]; then bash ./scripts/update-local-package.sh "{{package}}"; else bash ./scripts/update-local-package.sh; fi

[doc("Rotate the encrypted GPG backup gist from the current local key")]
rotate-gpg-gist:
    nix run .#rotate-gpg-gist

[doc("Show the GPG gist rotation actions without writing to GitHub")]
rotate-gpg-gist-dry:
    nix run .#rotate-gpg-gist -- --dry-run

[doc("Install the pre-commit hook")]
install-hooks:
    mkdir -p .git/hooks
    printf '#!/usr/bin/env bash\nexec nix run .#pre-commit-wrapper "$@"\n' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "Installed pre-commit hook"
