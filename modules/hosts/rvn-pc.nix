{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-pc" = config.flake.lib.mkHost {
    preset = "desktop";

    hostImports = [
      ../../machines/desktop/configuration.nix
      ../../machines/desktop/hardware-configuration.nix
      (
        { pkgs, ... }:
        {
          # environment.sessionVariables = {
          #   GSK_RENDERER = "cairo";
          #   WLR_RENDERER_ALLOW_SOFTWARE = "1";
          #   TERMINAL = "foot";
          # };

          # security.sudo.extraConfig = ''
          #   Defaults timestamp_timeout = 120
          # '';

          # environment.systemPackages = [
          #   pkgs.local.chromium-realforce
          # ];
        }
      )
    ];

    extraNixos = [
      "secrets"
      "nas"
      "gaming"
    ];
    # extraNixos = [ "hardware/fingerprint" ];

    extraHomeManager = [
      config.flake.modules.homeManager.dotfiles
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
    ];

    inherit (config.flake.meta.user) username;
  };
}
