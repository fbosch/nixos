# Secrets Management

## Setting up a new machine

1. **Import GPG key** (for manual secret editing):

   - Retrieve your GPG private key from Bitwarden
    - Import it directly from the clipboard:

    ```bash
    # Copy GPG private key from Bitwarden to clipboard, then:
    pbpaste | gpg --import  # macOS
    # or
    xclip -o | gpg --import  # Linux
   ```

2. **Build system** (auto-generates age key):

   ```bash
   # NixOS
   sudo nixos-rebuild switch --flake .#hostname
   
   # Darwin/macOS
   darwin-rebuild switch --flake .#hostname
   ```

3. **Add age key to .sops.yaml**:

   ```bash
   ./scripts/bootstrap-age.sh
   ```

4. **Commit and rebuild**:

   ```bash
   git add .sops.yaml
   git commit -m "Add age key for hostname"
   
   # NixOS
   sudo nixos-rebuild switch --flake .#hostname
   
   # Darwin/macOS
   darwin-rebuild switch --flake .#hostname
   ```

5. **Verify secrets available**:
   ```bash
   # NixOS
   ls -la /run/secrets/
   
   # Darwin/macOS (Home Manager)
   ls -la ~/.config/sops-nix/secrets/
   ```

## Daily usage

Edit secrets:

```bash
sops secrets/common.yaml
sops secrets/apis.yaml
sops secrets/containers.yaml
sops secrets/development.yaml
```

View secrets:

```bash
sops -d secrets/common.yaml
```

## How it works

- **Age key**: Auto-generated on first build
  - NixOS: `/var/lib/sops-nix/key.txt`
  - Darwin: `~/.config/sops/age/keys.txt`
  - Used for automated decryption during system activation
   - Keep recovery copies outside this repository in an encrypted backup system
  
- **GPG key**: Stored in Bitwarden
  - Used for manual secret editing with `sops`
  - Disaster recovery if all machines are lost
   - Recovery recipient for the repository secrets files

## Recipient changes

Recipient rules are separated by secret class. After changing `.sops.yaml`, run
`./scripts/update-sops-keys.sh` from a machine that can decrypt every affected
file. The script updates temporary copies first and replaces the repository
files only after every update succeeds.

Current runtime recipients are derived from host imports:

- `common.yaml` and `apis.yaml`: `rvn-pc`, `rvn-srv`, and the Mac system key.
- `containers.yaml`: `rvn-srv`.
- `development.yaml`: `rvn-pc`, `rvn-srv`, and the Mac system key.

`fbb-user` is retained for Home Manager decryption. Verify its private key is
installed at the configured Home Manager age-key path before removing it. The
`admin` GPG key is retained as the offline/manual recovery recipient.

## Moving NextDNS

`nextdns-profile-id` belongs in `common.yaml` because both the PC and server
consume it. Before activating this configuration, use SOPS to copy the value
from `containers.yaml` into `common.yaml`, then remove it from
`containers.yaml`. Run `./scripts/update-sops-keys.sh` afterwards to apply the
recipient rules.
