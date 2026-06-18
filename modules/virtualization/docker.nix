{ config, ... }:
{
  flake.modules.nixos."virtualization/docker" =
    { pkgs, ... }:
    {
      # Docker
      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
      };

      users.groups.docker.members = [ config.flake.meta.user.username ];

      environment.systemPackages = with pkgs; [
        docker-compose
      ];

      networking.firewall.trustedInterfaces = [ "docker0" ];
    };
}
