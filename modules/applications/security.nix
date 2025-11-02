{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      pass
      gnupg
      pinentry-curses
      protonvpn-gui
      bitwarden-desktop
    ];
  };
}
