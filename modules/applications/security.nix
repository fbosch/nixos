{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      firejail
      pass
      gnupg
      pinentry-curses
      protonvpn-gui
      bitwarden-desktop
    ];
  };
}
