let
  packagesFor =
    pkgs: with pkgs; [
      wezterm
      foot
      kitty
      ghostty
    ];
in
{
  flake.modules = {
    nixos.desktop = { pkgs, ... }: {
      environment.systemPackages = packagesFor pkgs;
    };
  };
}
