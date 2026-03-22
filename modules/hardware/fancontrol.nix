{
  flake.modules.nixos."hardware/fancontrol" =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        liquidctl
        lm_sensors
      ];

      services.udev.packages = with pkgs; [
        liquidctl
      ];
    };
}
