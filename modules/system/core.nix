{ inputs, lib, config, ... }:
{
  flake.modules.nixos.system = {
    # Centralize nixpkgs overlays for all NixOS hosts
    nixpkgs.overlays = [
      inputs.self.overlays.default
      inputs.nix-webapps.overlays.lib
      inputs.nix-webapps.overlays.default
      inputs.self.overlays.chromium-webapps-hardening
      inputs.self.overlays.proton-core-fix
    ];
    programs.nix-ld.enable = true;

    nixpkgs.config = {
      allowUnfreePredicate = pkg:
        let name = lib.getName pkg; in builtins.elem name (config.flake.meta.unfree.allowList or [ ]);
    };

    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [ "root" "@wheel" ];
        auto-optimise-store = true;
        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ5QK1Z5X2N7A5AZGk="
          "nix-community.cachix.org-1:mB9FQ9Zf9hKXf2n1eEF2Q84F1Jr9H1+GJdG6HCmYf8w="
        ];
      };

      gc = {
        automatic = false;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };

      optimise.automatic = true;
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";
    };
  };
}
