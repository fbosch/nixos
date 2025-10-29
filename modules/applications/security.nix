{
  flake.modules.homeManager.applications.security = { pkgs, ... }: {
    home.packages = with pkgs; [
      pass
      gnupg
      pinentry-curses
      bitwarden-desktop
      protonvpn-gui
      protonvpn-cli
    ];
  };
}
