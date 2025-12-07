# Secrets Management

## Setup

1. Get your GPG fingerprint:
   ```bash
   gpg --list-secret-keys --keyid-format=long
   ```

2. Update `.sops.yaml` with your fingerprint

3. Create and edit secrets:
   ```bash
   cp secrets.yaml.example secrets.yaml
   nix run nixpkgs#sops -- secrets/secrets.yaml
   ```

4. Add your GitHub token (from `gh auth token`)

5. Enable in your host config:
   ```nix
   imports = [ config.flake.modules.nixos.secrets ];
   ```

6. Rebuild:
   ```bash
   sudo nixos-rebuild switch --flake .#hostname
   ```

## Usage

Edit secrets:
```bash
nix run nixpkgs#sops -- secrets/secrets.yaml
```

## Notes

- Encrypted `secrets.yaml` is safe to commit
- Secrets decrypted automatically at boot to `/run/secrets/`
