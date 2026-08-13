{ inputs
, lib
, config
, ...
}:
let
  mkCachixConfig =
    isCorporateHost:
    lib.optionalAttrs (!isCorporateHost) {
      extra-substituters = lib.mkBefore [
        "https://fbosch.cachix.org"
      ];
      extra-trusted-public-keys = [
        "fbosch.cachix.org-1:QGKDLpPb1MY7YtcCvFpDNqQzGsYtDgE3YyC6IXK1nO8="
      ];
    };
  # Shared Cachix configuration for both NixOS and Darwin
  sharedCachixConfig = mkCachixConfig false;

  # Shared nix settings for both NixOS and Darwin
  sharedNixSettings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # This repository's flake declares its binary caches for bootstrap builds.
    accept-flake-config = true;
    fallback = true;
  };

  sharedNixSettingsMerged = lib.mkMerge [
    sharedNixSettings
    sharedCachixConfig
  ];

  # Shared home-manager config
  sharedHomeManagerConfig = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    overwriteBackup = true;
  };

  mkDarwinEnvironmentVariables =
    hostKey: hostMeta:
    lib.mkMerge [
      {
        NH_DARWIN_HOST = hostKey;
        NH_FLAKE = "/Users/${hostMeta.primaryUser}/nixos";
      }
      (lib.optionalAttrs (hostMeta.corporate or false) {
        CORPORATE = "1";
      })
    ];
in
{
  flake.modules.nixos.system = {
    # Centralize nixpkgs overlays for all NixOS hosts
    nixpkgs.overlays = [
      inputs.self.overlays.default
      inputs.nix-bwrapper.overlays.default
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
    environment.variables.NH_FLAKE = "/home/${config.flake.meta.user.username}/nixos";

    nix = {
      settings = lib.mkMerge [
        sharedNixSettingsMerged
        {
          allowed-users = [
            "root"
            "@wheel"
          ];

          trusted-users = [
            "root"
            "@wheel"
          ];
        }
      ];

      # Garbage collection is handled by nh
      gc.automatic = false;
      optimise.automatic = true;
    };

    home-manager = sharedHomeManagerConfig;

  };

  flake.modules.darwin.system =
    { hostMeta, hostKey, ... }:
    let
      isCorporateHost = hostMeta.corporate or false;
      usesDeterminateNix = hostMeta.nixDistribution == "determinate";
    in
    {
      # Centralize nixpkgs overlays for Darwin hosts
      nixpkgs.overlays = [
        inputs.self.overlays.default
        inputs.nix-bwrapper.overlays.default
      ];

      # Allow unfree packages (using simple allowUnfree for Darwin)
      nixpkgs.config.allowUnfree = true;

      environment.variables = mkDarwinEnvironmentVariables hostKey hostMeta;

      nix = lib.mkIf (!usesDeterminateNix) {
        settings = lib.mkMerge [
          sharedNixSettings
          (mkCachixConfig isCorporateHost)
          {
            trusted-users = [
              "root"
              "@admin"
            ];
          }
        ];

        # Garbage collection is handled by nh
        gc.automatic = false;
        optimise.automatic = true;
      };

      home-manager = sharedHomeManagerConfig;
    };

}
