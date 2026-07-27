_: {
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    let
      lact = pkgs.lact.override {
        libdisplay-info = pkgs.libdisplay-info_0_2;
      };
    in
    {
      environment.systemPackages = [ lact ];

      systemd.packages = [ lact ];
      systemd.services.lactd = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
      };
    };
}
