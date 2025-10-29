{
  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = with pkgs; [
      wezterm
      kitty
      ghostty
    ];
  };
}
