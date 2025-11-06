{
  flake.modules.nixos.winapps = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      freerdp
      xdg-utils
    ];
  };

  flake.modules.homeManager.winapps = { pkgs, inputs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      home.packages = [
        inputs.winapps.packages.${system}.winapps
        inputs.winapps.packages.${system}.winapps-launcher
        pkgs.freerdp
      ];

      # XDG desktop integration
      xdg.mimeApps.enable = true;

      # Create winapps configuration directory
      home.file.".config/winapps/.keep".text = "";
    };
}
