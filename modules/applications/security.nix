{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        pass
        gnupg
        pinentry-curses
        bitwarden-desktop
      ];

      services.flatpak.packages = [ "org.keepassxc.KeePassXC" ];
    };
}
