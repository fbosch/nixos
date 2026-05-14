_: {
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lact ];

      systemd.packages = [ pkgs.lact ];
      systemd.services.lact.enable = true;
    };
}
