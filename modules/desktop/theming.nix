{
  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = with pkgs; [
      pavucontrol
      adw-gtk3
      colloid-gtk-theme
    ];
  };
}
