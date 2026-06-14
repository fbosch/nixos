{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
in
{
  flake.modules.nixos.hardware =
    { pkgs, ... }:
    let
      lazyEvemu =
        map
          (
            exe:
            lazyApp pkgs {
              inherit exe;
              pkg = pkgs.evemu;
            }
          )
          [
            "evemu-describe"
            "evemu-device"
            "evemu-event"
            "evemu-play"
            "evemu-record"
          ];
    in
    {
      environment.systemPackages = [ pkgs.evtest ] ++ lazyEvemu;

      # Allow user access to Realforce keyboard for WebHID configuration
      services.udev.extraRules = ''
        # Topre Realforce keyboards - grant user access for configuration tools
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0853", ATTRS{idProduct}=="0317", GROUP="input", MODE="0660", TAG+="uaccess"
      '';
    };
}
