{
  flake.modules.nixos.winapps = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      freerdp
      xdg-utils
    ];
  };

  flake.modules.homeManager.winapps = { pkgs, inputs, ... }: {
    home.packages = [
      inputs.winapps.packages.${pkgs.system}.winapps
      inputs.winapps.packages.${pkgs.system}.winapps-launcher
      pkgs.freerdp
    ];

    # XDG desktop integration
    xdg.mimeApps.enable = true;

    # Create winapps configuration directory
    home.file.".config/winapps/.keep".text = "";
  };
}
