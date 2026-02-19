{ inputs
, lib
, config
, ...
}:
let
  # Shared Cachix configuration for both NixOS and Darwin
  sharedCachixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://fbosch.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "fbosch.cachix.org-1:QGKDLpPb1MY7YtcCvFpDNqQzGsYtDgE3YyC6IXK1nO8="
    ];
  };

  # Shared nix settings for both NixOS and Darwin
  sharedNixSettings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  } // sharedCachixConfig;

  # NixOS-specific nix settings
  nixosNixSettings = sharedNixSettings // {
    auto-optimise-store = true;
  };

  # Shared home-manager config
  sharedHomeManagerConfig = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
  };
in
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
      settings = nixosNixSettings // {
        trusted-users = [
          "root"
          "@wheel"
        ];
      };

      # Garbage collection is handled by nh
      gc.automatic = false;
      optimise.automatic = true;
    };

    home-manager = sharedHomeManagerConfig;

  };

  flake.modules.darwin.system = {
    # Allow unfree packages (using simple allowUnfree for Darwin)
    nixpkgs.config.allowUnfree = true;

    nix = {
      settings = sharedNixSettings // {
        trusted-users = [
          "root"
          "@admin"
        ];
      };

      # Garbage collection is handled by nh
      gc.automatic = false;
      optimise.automatic = true;
    };

    home-manager = sharedHomeManagerConfig;
  };
}
