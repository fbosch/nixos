{
  flake.modules.nixos.hardware = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [ evemu evtest ];

    # Allow user access to Realforce keyboard for WebHID configuration
    services.udev.extraRules = ''
      # Topre Realforce keyboards - grant user access for configuration tools
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0853", ATTRS{idProduct}=="0317", MODE="0660", TAG+="uaccess"
    '';
  };
}
