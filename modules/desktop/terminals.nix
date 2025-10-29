{
  flake.modules.homeManager.desktop.terminals = { pkgs, ... }: {
    home.packages = with pkgs; [
      wezterm
      kitty
      ghostty
    ];
  };
}
