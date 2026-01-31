{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        hardinfo2
        local.chromium-realforce # Realforce keyboard configuration tool
      ];

      # Flatpak system utilities
      # Note: Flatpak overrides are centralized in flatpak.nix
      services.flatpak.packages = [
        "org.gnome.World.PikaBackup" # Backup solution
      ];
    };
}
