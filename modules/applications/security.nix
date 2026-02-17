{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        pass
        gnupg
        pinentry-curses
      ];

      services.flatpak.packages = [
        "org.keepassxc.KeePassXC"
        "com.bitwarden.desktop"
      ];
    };
}
