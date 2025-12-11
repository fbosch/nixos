{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-vm" = config.flake.lib.mkHost {
    preset = "desktop";

    hostImports = [
      ../../machines/virtualbox-vm/configuration.nix
      ../../machines/virtualbox-vm/hardware-configuration.nix
      ({ pkgs, ... }: {
        environment.sessionVariables = {
          GSK_RENDERER = "cairo";
          WLR_RENDERER_ALLOW_SOFTWARE = "1";
        };

        security.sudo.extraConfig = ''
          Defaults timestamp_timeout = 120
        '';

        environment.systemPackages = [
          inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.chromium-realforce
        ];
      })
    ];

    extraNixos = [ "secrets" "nas" ];

    extraHomeManager = [
      config.flake.modules.homeManager.dotfiles
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
    ];

    inherit (config.flake.meta.user) username;
  };
}
