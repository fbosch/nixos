{ inputs, ... }:
{
  flake.modules.nixos.system = {
    # Centralize nixpkgs overlays for all NixOS hosts
    nixpkgs.overlays = [
      inputs.self.overlays.default
      inputs.nix-webapps.overlays.lib
      inputs.nix-webapps.overlays.default
      inputs.self.overlays.chromium-webapps-hardening
    ];
    programs.nix-ld.enable = true;

    nixpkgs.config.allowUnfree = true;

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "root" "@wheel" ];
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";
    };
  };
}
