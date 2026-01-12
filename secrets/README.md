# Secrets Management

## Setting up a new machine

1. **Import GPG key** (for manual secret editing):

   - Retrieve your GPG private key from Bitwarden
   - Save it to a temporary file:
   
   ```bash
   # Copy GPG private key from Bitwarden to clipboard, then:
   pbpaste > /tmp/private.key  # macOS
   # or
   xclip -o > /tmp/private.key  # Linux
   
   # Import the key
   gpg --import /tmp/private.key
   
   # Clean up
   rm /tmp/private.key
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
sops secrets/secrets.yaml
```

View secrets:

```bash
sops -d secrets/secrets.yaml
```

## How it works

- **Age key**: Auto-generated on first build
  - NixOS: `/var/lib/sops-nix/key.txt`
  - Darwin: `~/.config/sops/age/keys.txt`
  - Used for automated decryption during system activation
  - Backed up in `secrets/<hostname>-age-key.txt` (gitignored)
  
- **GPG key**: Stored in Bitwarden
  - Used for manual secret editing with `sops`
  - Disaster recovery if all machines are lost
  - Both keys can decrypt the same secrets file
