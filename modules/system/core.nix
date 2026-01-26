{ inputs
, lib
, config
, ...
}:
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

    # Disable systemd TPM2 setup services - they wait for measured UKI which we don't use
    # This prevents a 60+ second timeout during boot
    systemd.services = {
      systemd-tpm2-setup-early.enable = false;
      systemd-tpm2-setup.enable = false;

      # Disable NetworkManager-wait-online - most systems don't need to block boot for network
      # This saves ~5 seconds during boot
      NetworkManager-wait-online.enable = false;
    };

    # Enable ~/.local/bin in PATH for user-installed binaries (e.g. uv tools)
    environment.localBinInPath = true;

    nixpkgs.config = {
      allowUnfreePredicate =
        pkg:
        let
          name = lib.getName pkg;
        in
        builtins.elem name (config.flake.meta.unfree.allowList or [ ]);
    };

    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@wheel"
        ];
        auto-optimise-store = true;
        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
          "https://fbosch.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ5QK1Z5X2N7A5AZGk="
          "nix-community.cachix.org-1:mB9FQ9Zf9hKXf2n1eEF2Q84F1Jr9H1+GJdG6HCmYf8w="
          "fbosch.cachix.org-1:QGKDLpPb1MY7YtcCvFpDNqQzGsYtDgE3YyC6IXK1nO8="
        ];
      };

      # Garbage collection is handled by nh (see modules/system/nh.nix)
      # which provides a better interface and is configured to keep 15 generations
      # and clean anything older than 7 days
      gc.automatic = false;

      # Automatic store optimization runs periodically to deduplicate files
      optimise.automatic = true;
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";
    };

  };
}
