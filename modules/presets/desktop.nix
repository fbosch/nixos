{ inputs, ... }:
{
  # Desktop preset - full desktop environment with all features
  # Replaces the mkHost preset="desktop" pattern with explicit dendritic imports
  #
  # Based on config.flake.meta.presets.desktop:
  #   modules: users, fonts, security, desktop, applications, development, shell
  #   nixos: system, vpn
  #   homeManager: dotfiles

  flake.modules.nixos."presets/desktop" = with inputs.self.modules.nixos; {
    imports = [
      # Common modules
      users
      fonts
      security
      desktop
      applications
      development
      shell

      # NixOS-specific
      system
      vpn
    ];
  };

  # For Home Manager contexts (e.g., macOS with home-manager only)
  flake.modules.homeManager."presets/desktop" = with inputs.self.modules.homeManager; {
    imports = [
      # All desktop features for home-manager-only systems
      users
      dotfiles
      security
      desktop
      applications
      development
      shell
    ];
  };
}
