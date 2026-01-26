{ inputs, ... }:
{
  # Server preset - combines common server modules
  # Replaces the mkHost preset="server" pattern with explicit dendritic imports
  #
  # Based on config.flake.meta.presets.server:
  #   modules: users, security, development, shell
  #   nixos: system, vpn
  #   homeManager: dotfiles

  flake.modules.nixos."presets/server" = with inputs.self.modules.nixos; {
    imports = [
      # Common modules
      users
      security
      development
      shell

      # NixOS-specific
      system
      vpn
    ];
  };

  # For Home Manager contexts (e.g., macOS with home-manager only)
  flake.modules.homeManager."presets/server" = with inputs.self.modules.homeManager; {
    imports = [
      # Common modules
      users
      dotfiles
      security
      development
      shell
    ];
  };
}
