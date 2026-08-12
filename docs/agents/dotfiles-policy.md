# Dotfiles Ownership Policy

User dotfiles are managed in a separate repository at `~/dotfiles` using GNU Stow. The checkout remains independently usable and mutable without a Nix rebuild.

## Owners

- NixOS and nix-darwin own machine state: accounts and login authorization, hardware, privileged and system services, system security policy, desktop infrastructure, virtualization runtimes, fonts, and generally available packages.
- Home Manager owns user state and sessions: generated files under `$HOME`, XDG and MIME state, user services, user-scoped secrets, session variables, and material `programs.*` configuration.
- Stow owns portable, hand-maintained configuration that is safe to edit and deploy independently of Nix.

Package installation and program configuration are separate decisions. A package may be system-owned while its per-user configuration remains Stow- or Home Manager-owned.

## Path Boundaries

Each managed file has one writer. Avoid Home Manager child files below directories Stow links unless the leaf is an explicitly documented, ignored generated-file handoff.

| Path or responsibility | Owner |
| --- | --- |
| `~/.config/fish/**` hand-maintained configuration | Stow |
| Darwin machine context (`NH_DARWIN_HOST`, and `CORPORATE=1` on corporate hosts) | nix-darwin `environment.variables`, loaded through its Fish integration |
| `~/.gitconfig` portable identity, aliases, signing, and GitHub username | Stow |
| `~/.config/nix/git/config` generated platform helper and host maintenance include | Home Manager |
| GTK roots, CSS, and Nemo bookmarks on managed Linux desktops | Home Manager |
| SSH login `authorized_keys` | NixOS or nix-darwin machine configuration |
| SSH client configuration, private key, generated public key, and user agent | Home Manager |
| MIME associations and desktop entries | Home Manager |
| Terminal and editor hand-maintained configuration | Stow |

Stow must not deploy runtime state such as `.direnv`, and automated activation must never use `stow --adopt`.

## Cross-Repository Changes

The Nix and dotfiles repositories can update independently. A path transfer requires an explicit compatibility window in which old and new revisions interoperate. Compatibility code must identify its removal condition and must not overwrite unknown user files or symlinks.

When adding or changing a generated user path, validate all ancestors with `lstat`. Use atomic replacement for generated secret or session files, except for documented Stow handoffs that have an established safe writer.
