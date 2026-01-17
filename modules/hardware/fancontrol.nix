{
  flake.modules.nixos."hardware/fancontrol" =
    { pkgs, ... }:
    {
      programs.coolercontrol.enable = true;

      environment.systemPackages = with pkgs; [
        liquidctl
        lm_sensors
      ];

      services.udev.packages = with pkgs; [
        liquidctl
      ];
    };
}
