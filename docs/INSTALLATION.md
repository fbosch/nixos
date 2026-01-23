# Installation Guide

## 1. Create Bootable USB

- Download NixOS ISO from nixos.org/download
- Create bootable USB installation media

## 2. Boot from USB

- Insert USB drive and restart computer
- Enter BIOS/UEFI (usually F2, F12, Del, or Esc during boot)
- Set USB as first boot device
- Save and reboot

## 3. Use Installer

- Select "Graphical ISO image" from boot menu
- Follow the graphical installer to partition disk and configure system
- Complete the installation through the GUI

## 4. Post-Installation Setup

- Reboot and remove USB drive
- Log in with the user account created during installation
- Open a terminal to begin configuring your system

## 5. Setup GitHub CLI

- Run `nix-shell -p gh` to enter a temporary shell with GitHub CLI
- Run `gh auth login`
- Choose SSH protocol
- Choose "Login with a web browser" (device authentication method)
- Follow the prompts to authenticate from another device

## 6. Clone and Setup Configuration

- Run `gh repo clone fbosch/nixos` to clone your configuration repository
- Copy `/etc/nixos/*` to `~/nixos/machines/<name>/`

## 7. Add Host Configuration

- Create a new host file in `modules/hosts/<name>.nix` following the pattern of existing hosts
- Ensure the host file references the machine configuration from `machines/<name>/`
- Configure the host with appropriate settings for your machine
- Add the `secrets` module in the host `modules = [ ... ]` list
- Navigate to the `~/nixos` directory
- Run `sudo nixos-rebuild switch --flake .#<hostname>` to build and apply the configuration

## 8. Import GPG Key

- Enter a shell with the Bitwarden CLI available: `nix-shell -p bitwarden-cli`
- Point the CLI at your self-hosted vault: `bw config server https://vault.corvus-corax.synology.me`
- Log in: `bw login`
- Write the key note to a file: `bw get item "GPG Private Key" --session "$(bw unlock --raw)" | jq -r '.notes' > private.key`
- Import the key: `gpg --import private.key`

## 9. Bootstrap SOPS Age Key

- Run `./scripts/bootstrap-age.sh` from the `~/nixos` directory
- Review and commit the updated `.sops.yaml`
- Rebuild: `sudo nixos-rebuild switch --flake .#<hostname>`
