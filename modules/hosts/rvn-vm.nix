{ inputs
, config
, ...
}:
let
  hostMeta = {
    name = "rvn-vm";
    sshAlias = "vm";
    tailscale = null;
    local = null;
    sshPublicKey = null;
  };
in
{
  # rvn-vm: Dendritic host configuration for VirtualBox VM
  # Hardware: VirtualBox virtual machine
  # Role: Testing and development environment

  flake.meta.hosts = [ hostMeta ];

  flake.modules.nixos."hosts/rvn-vm" =
    { ... }:
    {
      imports = config.flake.lib.resolve [
        # Desktop preset (users, fonts, security, desktop, applications, development, shell, system, vpn)
        "presets/desktop"

        # system
        "secrets"
        "nas"

        # hardware configuration
        ../../machines/virtualbox-vm/configuration.nix
        ../../machines/virtualbox-vm/hardware-configuration.nix
        inputs.grub2-themes.nixosModules.default
      ];

      # Home Manager configuration for user
      home-manager.users.${config.flake.meta.user.username}.imports =
        config.flake.lib.resolveHm [
          # Desktop preset (includes users, dotfiles, fonts, security, desktop, applications, development, shell)
          "presets/desktop"

          # Shared modules with Home Manager components
          "secrets"
        ]
        ++ [
          # External Home Manager modules
          inputs.flatpaks.homeManagerModules.nix-flatpak
          inputs.vicinae.homeManagerModules.default
        ];

      # VirtualBox-specific environment variables for software rendering
      environment.sessionVariables = {
        GSK_RENDERER = "cairo";
        WLR_RENDERER_ALLOW_SOFTWARE = "1";
        TERMINAL = "foot";
      };

      # Extend sudo timeout for VM convenience
      security.sudo.extraConfig = ''
        Defaults timestamp_timeout = 120
      '';
    };
}
