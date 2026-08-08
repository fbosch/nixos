# Dotfiles Ownership Policy

User dotfiles are managed in a separate repository at `~/dotfiles` using GNU Stow. The checkout remains independently usable and mutable without a Nix rebuild.

## Owners

- NixOS and nix-darwin own machine state: accounts and login authorization, hardware, privileged and system services, system security policy, desktop infrastructure, virtualization runtimes, fonts, and generally available packages.
- Home Manager owns user state and sessions: generated files under `$HOME`, XDG and MIME state, user services, user-scoped secrets, session variables, and material `programs.*` configuration.
- Stow owns portable, hand-maintained configuration that is safe to edit and deploy independently of Nix.

Package installation and program configuration are separate decisions. A package may be system-owned while its per-user configuration remains Stow- or Home Manager-owned.

## Path Boundaries

Each managed path has one writer. Home Manager must not create a child below a directory Stow links. Generated Home Manager files belong outside Stow-owned trees; Stow may source or include them from a documented compatibility path.

| Path or responsibility | Owner |
| --- | --- |
| `~/.config/fish/**` hand-maintained configuration | Stow |
| Generated Fish host and secret state | Home Manager, outside `~/.config/fish` |
| `~/.gitconfig` portable identity, aliases, signing, and GitHub username | Stow |
| Generated Git platform helper and host maintenance include | Home Manager |
| GTK roots, CSS, and Nemo bookmarks on managed Linux desktops | Home Manager |
| SSH login `authorized_keys` | NixOS or nix-darwin machine configuration |
| SSH client configuration, private key, generated public key, and user agent | Home Manager |
| MIME associations and desktop entries | Home Manager |
| `.npmrc` and `.wakatime.cfg` rendered user secret files | Home Manager |
| Terminal and editor hand-maintained configuration | Stow |

Stow must not deploy runtime state such as `.direnv`, and automated activation must never use `stow --adopt`.

## Cross-Repository Changes

The Nix and dotfiles repositories can update independently. A path transfer requires an explicit compatibility window in which old and new revisions interoperate. Compatibility code must identify its removal condition and must not overwrite unknown user files or symlinks.

When adding or changing a generated user path, validate all ancestors with `lstat`; a safe leaf does not make a Stow-linked parent safe. Use atomic replacement for generated secret or session files.
