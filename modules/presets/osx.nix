{ config, ... }:
{
  flake.modules = {
    darwin."presets/osx" = {
      imports = config.flake.lib.resolveDarwin [
        "system"
        "development"
        "shell"
        "virtualization/podman"
        "aerospace"
        "alt-tab"
        "cleanshot"
        "fonts"
        "hazeover"
        "system-defaults"
        "security"
        "homebrew"
      ];
    };

    homeManager."presets/osx" = {
      imports = config.flake.lib.resolveHm [
        "dotfiles"
        "fonts"
        "security"
        "development"
        "worktrunk"
        "shell"
        "virtualization/podman"
      ];
    };
  };
}
