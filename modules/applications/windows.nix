{ inputs, ... }:
{
  flake.modules.nixos.windows =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        freerdp
        xdg-utils
      ];
    };

  flake.modules.homeManager.windows =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        winboat
        inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps
        inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps-launcher
        freerdp
      ];

      services.flatpak.packages = [
        "com.usebottles.bottles"
      ];

      # XDG desktop integration
      xdg.mimeApps.enable = true;

      home.file = {
        ".config/winapps/.keep".text = "";

        ".config/winapps/winapps.conf".text = ''
          # USB devices to pass through to Windows VM
          # Format: RDP_USB0="0853:0317" for REALFORCE keyboard
          RDP_USB0="0853:0317"
        '';
      };

    };
}
