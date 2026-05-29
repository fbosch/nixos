_: {
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lact ];

      systemd.packages = [ pkgs.lact ];
      systemd.services.lactd = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
      };
    };
}
