{
  flake.modules.nixos.hardware =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.evtest
        pkgs.evemu
      ];

      # Allow user access to Realforce keyboard for WebHID configuration
      services.udev.extraRules = ''
        # Topre Realforce keyboards - grant user access for configuration tools
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0853", ATTRS{idProduct}=="0317", GROUP="input", MODE="0660", TAG+="uaccess"
      '';
    };
}
