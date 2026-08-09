{
  flake.modules = {
    nixos.applications = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        pass
        gnupg
        pinentry-curses
        bitwarden-desktop
      ];
    };
    homeManager.applications = {
      services.flatpak.packages = [
        "org.keepassxc.KeePassXC"
      ];
    };
  };
}
