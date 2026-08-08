let
  packagesFor =
    pkgs: with pkgs; [
      pass
      gnupg
      pinentry-curses
      bitwarden-desktop
    ];
in
{
  flake.modules = {
    nixos.applications = { pkgs, ... }: {
      environment.systemPackages = packagesFor pkgs;
    };
    homeManager.applications = {
      services.flatpak.packages = [
        "org.keepassxc.KeePassXC"
      ];
    };
  };
}
