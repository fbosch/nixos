# Dotfiles Policy

User dotfiles are managed in a separate repository at `~/dotfiles` using GNU Stow.

**Never configure these programs** in this NixOS flake; they are managed exclusively through dotfiles:
- **Shell configurations**: Fish, Zsh, Bash (aliases, functions, scripts, abbreviations)
- **Editors**: Neovim, VSCode/Cursor
- **Terminal emulators**: Kitty, Foot, WezTerm
- **Desktop environment**: Hyprland, Hypr-dock, Waybar, Waycorner, Rofi, SwayNC
- **CLI tools**: Bat, Btop, fd, ripgrep, Lazygit, Gitui, Tmux, Mprocs, Vivid
- **Theming**: GTK-3.0, GTK-4.0, Starship
- **Other**: AGS, Palettum, OpenCode, nwg-look, Zeal, Astro

Only install packages for these programs in NixOS; leave all configuration to dotfiles.

If unsure whether a program is dotfiles-managed, check if it has a directory in `~/dotfiles/.config/`.
