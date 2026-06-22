{
  flake.modules.nixos.applications = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.vicinae ];
    systemd.packages = [ pkgs.vicinae ];

    systemd.user.targets.graphical-session.wants = [ "vicinae.service" ];
  };
}
