# Common Diagnostic Commands

Quick reference for NixOS debugging commands.

## NH (Nix Helper) - Recommended

This repository has `nh` available for better rebuild experience:

```bash
# Switch with confirmation prompt
nh os switch --ask

# Build without switching
nh os build

# Test without making default generation
nh os test

# See what would change
nh os switch --dry

# Update flake inputs then switch
nh os switch --update

# Clean old generations (keep last 5)
nh clean all --keep 5

# Search packages
nh search <package-name>
```

## Flake Inspection

```bash
# Show flake structure
nix flake show

# Show flake metadata
nix flake metadata

# List all outputs
nix eval .# --apply builtins.attrNames

# List nixosConfigurations
nix eval .#nixosConfigurations --apply builtins.attrNames

# Show specific configuration
nix eval .#nixosConfigurations.<hostname> --apply '(c: c.config.system.name)'
```

## Module Evaluation

```bash
# List all modules in class
nix eval .#modules.nixos --apply builtins.attrNames
nix eval .#modules.homeManager --apply builtins.attrNames
nix eval .#modules.generic --apply builtins.attrNames

# Check module structure
nix eval .#modules.nixos.myfeature --json

# Evaluate specific option
nix eval .#nixosConfigurations.<hostname>.config.services.myapp.enable

# Show all imports for a host
nix eval .#nixosConfigurations.<hostname>.config.imports --json
```

## Build Diagnosis

```bash
# Recommended: Use nh CLI (cleaner output)
nh os switch --ask              # Interactive switch with confirmation
nh os build                     # Build without switching
nh os test                      # Test without making it default

# Traditional nixos-rebuild commands
sudo nixos-rebuild build --flake .#hostname

# Build with detailed trace
sudo nixos-rebuild build --flake .#hostname --show-trace

# Dry-run (show what would change)
sudo nixos-rebuild dry-run --flake .#hostname

# Test activation without switch
sudo nixos-rebuild test --flake .#hostname
```

## System Inspection

```bash
# Current generation
ls -l /nix/var/nix/profiles/system

# List all generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system

# Compare two generations
nix store diff-closures \
  /nix/var/nix/profiles/system-{100,101}-link

# Show current configuration
nixos-option services.myapp
```

## Service Debugging

```bash
# Service status
systemctl status <service>

# Service logs
journalctl -u <service>
journalctl -u <service> -f  # Follow
journalctl -u <service> -b  # Since boot
journalctl -u <service> --since "1 hour ago"

# Service configuration
systemctl cat <service>

# Restart service
sudo systemctl restart <service>

# Check service dependencies
systemctl list-dependencies <service>
```

## SOPS Debugging

```bash
# Check age key exists
ls -la /var/lib/sops-nix/key.txt

# Get public age key
cat /var/lib/sops-nix/key.txt | \
  nix-shell -p age --run "age-keygen -y"

# Test decryption
nix-shell -p sops --run "sops -d secrets/common.yaml"

# Show which keys can decrypt
sops -i --show-keys secrets/common.yaml

# Re-encrypt with current keys
for f in secrets/*.yaml; do sops updatekeys "$f"; done
```

## Lint and Check

```bash
# Run repository lint
nix run .#lint

# Format all files
nix run .#fmt

# Full flake check
nix flake check

# Check without building
nix flake check --no-build

# Check with trace
nix flake check --show-trace
```

## Git and Version Control

```bash
# Check git status
git status

# Show uncommitted changes
git diff

# Show what's staged
git diff --staged

# Stash changes temporarily
git stash
git stash pop

# View recent commits
git log --oneline -10
```

## Garbage Collection

```bash
# Using nh (recommended)
nh clean all --keep 5          # Keep last 5 generations
nh clean all --keep-since 7d   # Keep last 7 days
nh clean user --keep 3         # Clean user profile, keep 3

# Traditional nix commands
# List old generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system

# Delete old generations (keep last 5)
sudo nix-env --delete-generations +5 -p /nix/var/nix/profiles/system

# Garbage collect
sudo nix-collect-garbage

# Delete all old generations and gc
sudo nix-collect-garbage -d

# Free up boot space
sudo nix-collect-garbage -d
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot
```

## Hardware and Boot

```bash
# List block devices
lsblk

# Show UUIDs
blkid

# Check boot loader entries
sudo efibootmgr -v  # UEFI
ls /boot/grub       # BIOS

# View kernel messages
dmesg | less
journalctl -k  # Kernel logs
```

## Network Debugging

```bash
# List network interfaces
ip link show

# Show IP addresses
ip addr show

# Check routes
ip route show

# NetworkManager status
nmcli device status
nmcli connection show

# Test connectivity
ping -c 3 1.1.1.1
curl -I https://cache.nixos.org
```

## User and Permissions

```bash
# Check user info
id <username>

# List all users
getent passwd

# List all groups  
getent group

# Check file permissions
ls -la /path/to/file

# Fix ownership
sudo chown user:group /path/to/file

# Fix permissions
sudo chmod 644 /path/to/file
```

## Performance and Resources

```bash
# System resource usage
htop

# Disk usage
df -h
du -sh /nix/store

# Check running processes
ps aux | grep <name>

# Memory info
free -h
```

## Package Management

```bash
# Using nh (recommended)
nh search <package-name>        # Search packages

# Traditional nix commands
# Search packages
nix search nixpkgs <name>

# Show package info
nix-env -qa --description <name>

# Which package provides a file
nix-locate <filename>

# Temporary shell with package
nix-shell -p <package>
```

## Rollback and Recovery

```bash
# Rollback to previous generation
sudo nixos-rebuild --rollback

# Rollback manually
sudo nix-env --rollback -p /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch

# Boot specific generation (from GRUB menu)
# Select "NixOS - Configuration X" at boot

# Switch to specific generation
sudo nix-env --switch-generation <number> -p /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

## Home Manager

```bash
# Home Manager generations
home-manager generations

# Build Home Manager config
home-manager build --flake .#user@hostname

# Switch Home Manager config
home-manager switch --flake .#user@hostname

# Home Manager rollback
home-manager rollback
```

## Quick Troubleshooting Chains

**Service won't start:**
```bash
systemctl status <service>
journalctl -u <service> -n 50
systemctl cat <service>
```

**Build fails:**
```bash
nh os build                      # Try with nh first
nix flake check --show-trace     # Or detailed trace
nix run .#lint
git diff
```

**Module not taking effect:**
```bash
nix eval .#modules.nixos --apply builtins.attrNames | grep mymodule
nix eval .#nixosConfigurations.<hostname>.config.imports
```

**SOPS secret issues:**
```bash
ls -la /var/lib/sops-nix/key.txt
sops -d secrets/common.yaml
cat .sops.yaml
```
