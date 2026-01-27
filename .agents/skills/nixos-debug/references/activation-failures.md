# Activation Failure Patterns

## Systemd Service Failures

### Pattern: "Failed to start X.service"

**Diagnosis workflow**:
```bash
# 1. Check service status
systemctl status <service-name>

# 2. View full logs
journalctl -u <service-name> -b

# 3. Check service configuration
systemctl cat <service-name>

# 4. Test service manually
systemctl start <service-name>
```

**Common causes**:

**Missing dependencies**:
```nix
# ✅ Add required services
systemd.services.myapp = {
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  requires = [ "postgresql.service" ];
};
```

**Wrong user/group**:
```nix
# Ensure user exists
users.users.myapp = {
  isSystemUser = true;
  group = "myapp";
};
users.groups.myapp = { };

systemd.services.myapp = {
  serviceConfig.User = "myapp";
  serviceConfig.Group = "myapp";
};
```

**Permission errors**:
```nix
# Fix directory permissions
systemd.tmpfiles.rules = [
  "d /var/lib/myapp 0750 myapp myapp -"
];
```

**Binary not in PATH**:
```nix
systemd.services.myapp = {
  path = with pkgs; [ git nodejs python3 ];  # Add to service PATH
  serviceConfig.ExecStart = "${pkgs.myapp}/bin/myapp";
};
```

---

## Home Manager Activation Failures

### Pattern: "Error while activating home-manager generation"

**Common error messages and fixes**:

**"Existing file at 'X' conflicts"**:
```
Existing file '/home/user/.config/nvim/init.vim' is in the way

Fix: Back up and remove conflicting file
```

**Diagnosis**:
```bash
# Check what file is conflicting
ls -la /home/user/.config/nvim/init.vim

# Backup if needed
mv /home/user/.config/nvim/init.vim{,.backup}

# Retry activation
sudo nixos-rebuild switch --flake .#hostname
```

**"Service 'X' not found"**:
```
Module home-manager references systemd service that doesn't exist
```

**Fix**: Check service name, ensure it's defined:
```nix
# ✅ Define service before referencing
systemd.user.services.myapp = {
  Unit.Description = "My App";
  Service.ExecStart = "${pkgs.myapp}/bin/myapp";
};

# Now can reference in other modules
systemd.user.services.other.after = [ "myapp.service" ];
```

---

## SOPS Decryption Failures

### Pattern: "Failed to decrypt SOPS secret" or "age key not found"

**Error messages**:
```
failed to get the data key required to decrypt the SOPS file
error: no age key found
```

**Diagnosis workflow**:
```bash
# 1. Check if age key exists
ls -la /var/lib/sops-nix/key.txt

# 2. Verify age key is in .sops.yaml
cat .sops.yaml | grep -A5 'age'

# 3. Test manual decryption
nix-shell -p sops --run "sops -d secrets/secrets.yaml"

# 4. Check secret file encryption keys
sops -i --show-keys secrets/secrets.yaml
```

**Common causes and fixes**:

**Age key not generated yet**:
```bash
# First build generates it automatically
sudo nixos-rebuild switch --flake .#hostname

# Then bootstrap it into .sops.yaml
./scripts/bootstrap-age.sh
```

**Age key not in .sops.yaml**:
```bash
# Run bootstrap script
./scripts/bootstrap-age.sh

# Commit updated .sops.yaml
git add .sops.yaml
git commit -m "Add age key for hostname"

# Rebuild
sudo nixos-rebuild switch --flake .#hostname
```

**Wrong age key in .sops.yaml**:
```bash
# Get correct public key
cat /var/lib/sops-nix/key.txt | nix-shell -p age --run "age-keygen -y"

# Update .sops.yaml with correct key
# Re-encrypt all secrets
sops updatekeys secrets/secrets.yaml
```

**Secret not encrypted with current keys**:
```bash
# Re-encrypt with current .sops.yaml keys
sops updatekeys secrets/secrets.yaml

# Or re-encrypt all secrets
find secrets -name "*.yaml" -exec sops updatekeys {} \;
```

**Permission issues on age key**:
```bash
# Check permissions (should be 600, owned by root)
ls -la /var/lib/sops-nix/key.txt

# Fix if needed (requires boot from rescue media)
sudo chmod 600 /var/lib/sops-nix/key.txt
sudo chown root:root /var/lib/sops-nix/key.txt
```

---

## File System Activation Errors

### Pattern: "Failed to mount X" or "device not found"

**Diagnosis**:
```bash
# Check filesystem configuration
nix eval .#nixosConfigurations.<hostname>.config.fileSystems --json | jq

# Verify device exists
lsblk
blkid

# Check mount point permissions
ls -lad /mnt/point

# Test mount manually
sudo mount /dev/disk/by-uuid/<uuid> /mnt/point
```

**Common fixes**:
```nix
# Use UUID instead of device path
fileSystems."/mnt/data" = {
  device = "/dev/disk/by-uuid/<uuid>";  # ✅ More reliable
  # device = "/dev/sda1";  # ❌ Can change between boots
};

# Add needed file system support
boot.supportedFilesystems = [ "ntfs" "btrfs" "zfs" ];

# Don't fail boot if mount fails (external drives)
fileSystems."/mnt/external" = {
  device = "/dev/disk/by-uuid/<uuid>";
  options = [ "nofail" ];  # ✅ Continue boot if missing
};
```

---

## User/Group Activation Errors

### Pattern: "Failed to create user/group X"

**Diagnosis**:
```bash
# Check if user already exists (outside NixOS)
id username

# Check configured users
nix eval .#nixosConfigurations.<hostname>.config.users.users --json | jq

# Check for UID/GID conflicts
getent passwd | sort -t: -k3 -n
getent group | sort -t: -k3 -n
```

**Common fixes**:
```nix
# Specify UID to avoid conflicts
users.users.myuser = {
  isNormalUser = true;
  uid = 1001;  # ✅ Explicit UID
};

# Handle existing user
users.users.existing = {
  isNormalUser = true;
  # NixOS will adopt existing user if UID matches
};

# System user for services
users.users.serviceuser = {
  isSystemUser = true;  # ✅ Not a login user
  group = "servicegroup";
};
```

---

## Boot Loader Activation Errors

### Pattern: "Failed to install bootloader" or "grub installation failed"

**Diagnosis**:
```bash
# Check bootloader config
nix eval .#nixosConfigurations.<hostname>.config.boot.loader --json | jq

# Verify EFI partition (UEFI systems)
ls -la /boot/EFI
efibootmgr -v

# Check BIOS/GRUB installation (BIOS systems)
sudo grub-install --version
ls -la /boot/grub
```

**Common fixes**:
```nix
# UEFI systems
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
boot.loader.efi.efiSysMountPoint = "/boot";  # Verify mount point

# BIOS systems  
boot.loader.grub = {
  enable = true;
  device = "/dev/sda";  # ✅ Disk, not partition
  # device = "/dev/sda1";  # ❌ Wrong for GRUB
};

# If EFI variables are read-only
boot.loader.efi.canTouchEfiVariables = false;  # ✅ Still boots, can't update boot order
```

---

## Network Activation Errors

### Pattern: "Failed to configure network interface X"

**Diagnosis**:
```bash
# List interfaces
ip link show
networkctl status

# Check NetworkManager status
systemctl status NetworkManager

# Test interface configuration
sudo networkctl reconfigure <interface>
```

**Common fixes**:
```nix
# Use NetworkManager (desktop systems)
networking.networkmanager.enable = true;

# Or systemd-networkd (servers)
networking.useNetworkd = true;

# Ensure interface name is correct
networking.interfaces.enp0s31f6 = {  # ✅ Use `ip link` to get exact name
  useDHCP = true;
};

# Disable conflicting network managers
networking.wireless.enable = false;  # If using NetworkManager
```

---

## Rollback on Activation Failure

### When activation fails, system rolls back

**Pattern**: Build succeeds but activation fails, system reverts to previous generation

**Check what failed**:
```bash
# View activation logs
journalctl -b -u nixos-upgrade

# Check what changed between generations
nix store diff-closures /nix/var/nix/profiles/system-{<old>,<new>}-link

# List recent generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system
```

**Manual rollback if needed**:
```bash
# Boot previous generation from GRUB menu
# Or rollback manually
sudo nix-env --rollback -p /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

**Test activation without switching**:
```bash
# Build but don't activate
sudo nixos-rebuild build --flake .#hostname

# Test activation on built system
sudo /nix/store/<new-system>/bin/switch-to-configuration test
```
