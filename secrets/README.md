# Secrets Management

1. **Bootstrap GPG key from Bitwarden**:

   ```bash
   nix-shell -p bitwarden-cli
   ./scripts/bootstrap-gpg.sh
   ```

2. **Verify GPG imported**:

   ```bash
   gpg --list-secret-keys
   sops -d secrets/secrets.yaml  # Test decryption
   ```

3. **Enable sops module and rebuild**:

   ```bash
   sudo nixos-rebuild switch --flake .#hostname
   ```

4. **Verify secrets available**:
   ```bash
   ls -la /run/secrets/
   ```

## Usage

Edit secrets:

```bash
sops secrets/secrets.yaml
```

View secrets:

```bash
sops -d secrets/secrets.yaml
```
