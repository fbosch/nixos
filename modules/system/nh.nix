{ config, ... }:
{
  flake.modules.nixos.system = { pkgs, ... }: {
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 7d --keep 15";
      flake = "/home/${config.flake.meta.user.username}/nixos";
    };

    environment.systemPackages = with pkgs; [
      nh
      nix-output-monitor
    ];
  };
}
