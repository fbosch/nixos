{
  flake.modules.homeManager.windows.winboat = { pkgs, ... }: {
    home.packages = with pkgs; [ winboat wine64 winetricks ];

    xdg.configFile."winboat/config.toml".text = ''
      [general]
      wine_path = "${pkgs.wine64}/bin/wine"
      winetricks_path = "${pkgs.winetricks}/bin/winetricks"
    '';
  };
}
