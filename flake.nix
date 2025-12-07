{
  description = "fbosch/nix";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  inputs = {
    # Core infrastructure
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Package infrastructure (modules/flake-parts/nixpkgs.nix, modules/system/core.nix)
    pkgs-by-name-for-flake-parts.url = "github:drupol/pkgs-by-name-for-flake-parts";
    nix-webapps = {
      url = "github:TLATER/nix-webapps";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "dedupe_systems";
    };

    # Dotfiles (modules/dotfiles.nix)
    dotfiles = {
      url = "github:fbosch/dotfiles";
      flake = false;
    };

    # Hyprland desktop environment (modules/desktop/hyprland.nix)
    hyprland = {
      url = "github:hyprwm/Hyprland?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "dedupe_systems";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    hyprland-contrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "dedupe_systems";
    };

    # Applications
    flatpaks.url = "github:gmodena/nix-flatpak"; # modules/applications/flatpak.nix
    vicinae = {
      # modules/applications/vicinae.nix
      url = "github:vicinaehq/vicinae";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    winapps = {
      # modules/applications/winapps.nix
      url = "github:winapps-org/winapps";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "dedupe_flake-utils";
        flake-compat.follows = "dedupe_flake-compat";
      };
    };
    ags = {
      url = "github:aylur/ags";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "dedupe_systems";
    };

    # Boot theming for VMs (machines/virtualbox-vm/configuration.nix)
    mac-style-plymouth = {
      url = "github:SergioRibera/s4rchiso-plymouth-theme";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "dedupe_flake-utils";
    };
    distro-grub-themes = {
      url = "github:AdisonCavani/distro-grub-themes";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "dedupe_flake-utils";
    };
  };

  # Inputs used only for deduplication via .follows
  # These are targets of at least one <input>.inputs.<input>.follows above.
  # If all .follows targeting these are removed, these inputs should be removed too.
  # Prefixed with dedupe_ for easy identification.
  inputs = {
    dedupe_systems.url = "github:nix-systems/default";

    dedupe_flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "dedupe_systems";
    };

    dedupe_flake-compat.url = "github:edolstra/flake-compat";
  };

}
