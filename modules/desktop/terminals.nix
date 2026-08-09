{
  flake.modules = {
    nixos.desktop = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        wezterm
        foot
        kitty
        ghostty
      ];
    };
  };
}
