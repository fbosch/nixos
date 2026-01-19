# SOPS Secrets Workflow (Age + GPG)

SOPS secrets use a dual-key approach.

**Age key (primary)**
- Used for automated decryption during system activation.
- Machine-specific age key auto-generated at `/var/lib/sops-nix/key.txt` on first build.
- Private key backed up in `secrets/<hostname>-age-key.txt` (gitignored).
- Public key must be added to `.sops.yaml` for secrets to decrypt.
- Configured via `sops.age.generateKey = true` in `modules/sops.nix`.

**GPG key (recovery)**
- Used for manual secret editing and disaster recovery.
- Backed up in Bitwarden; survives machine loss.
- Import to user keyring via `scripts/bootstrap-gpg.sh` for manual editing.
- Not needed for system activation (age key handles that).

Both keys can decrypt the same secrets file (multi-key encryption).

**Setting up a new machine**
1. `./scripts/bootstrap-gpg.sh` — Import GPG key for manual secret editing (optional but recommended)
2. `sudo nixos-rebuild switch --flake .#hostname` — Build system (auto-generates age key)
3. `./scripts/bootstrap-age.sh` — Add age key to `.sops.yaml` and re-encrypt secrets
4. Commit updated `.sops.yaml`: `git add .sops.yaml && git commit -m "Add age key for hostname"`
5. `sudo nixos-rebuild switch --flake .#hostname` — Rebuild to activate secrets
