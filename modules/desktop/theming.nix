{
  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = with pkgs; [
      pavucontrol
      nwg-look
      adw-gtk3
      colloid-gtk-theme
    ];
  };
}
