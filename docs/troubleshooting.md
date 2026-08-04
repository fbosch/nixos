# Troubleshooting

## macOS

### Existing `nix.custom.conf`

If nix-darwin reports an unexpected `/etc/nix/nix.custom.conf`, a prior Nix configuration already owns the file. Preserve it, then let nix-darwin recreate the file from `determinateNix.customSettings`:

```sh
sudo mv /etc/nix/nix.custom.conf /etc/nix/nix.custom.conf.before-nix-darwin
```

Migrate any required settings from the backup into `determinateNix.customSettings` before activating again.
