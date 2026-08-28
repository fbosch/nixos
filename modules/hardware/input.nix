{
  flake.modules.nixos.hardware =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.evtest
        pkgs.evemu
      ];

      # Keep browser configurator access scoped to supported device vendors.
      services.udev = {
        packages = [ pkgs.keychron-udev-rules ];
        extraRules = ''
          # Topre Realforce keyboards - grant user access for configuration tools
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0853", ATTRS{idProduct}=="0317", GROUP="input", MODE="0660", TAG+="uaccess"

          # 8BitDo controllers and receivers - grant user access for the web firmware updater
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="2dc8", MODE="0660", TAG+="uaccess"
        '';
      };
    };
}
