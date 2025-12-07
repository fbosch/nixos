# Secrets Management

## Setting up a new machine

1. **Import GPG key** (for manual secret editing):

   ```bash
   nix-shell -p bitwarden-cli gnupg
   ./scripts/bootstrap-gpg.sh
   ```

2. **Build system** (auto-generates age key):

   ```bash
   sudo nixos-rebuild switch --flake .#hostname
   ```

3. **Add age key to .sops.yaml**:

   ```bash
   nix-shell -p age sops
   ./scripts/bootstrap-age.sh
   ```

4. **Commit and rebuild**:

   ```bash
   git add .sops.yaml
   git commit -m "Add age key for hostname"
   sudo nixos-rebuild switch --flake .#hostname
   ```

5. **Verify secrets available**:
   ```bash
   ls -la /run/secrets/
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

- **Age key**: Auto-generated at `/var/lib/sops-nix/key.txt` on first build
  - Used for automated decryption during system activation
  - Backed up in `secrets/<hostname>-age-key.txt` (gitignored)
  
- **GPG key**: Stored in Bitwarden
  - Used for manual secret editing
  - Disaster recovery if all machines are lost
  - Both keys can decrypt the same secrets file
