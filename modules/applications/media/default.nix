let
  packagesFor =
    pkgs: with pkgs; [
      loupe
      plezy
      local."webapp/youtubemusic"
      local."webapp/synologyphotos"
    ];
in
{
  flake.modules = {
    nixos.applications = { pkgs, ... }: {
      environment.systemPackages = [
        # File previewer for Nemo file manager
        pkgs.sushi
      ]
      ++ packagesFor pkgs;
    };

    homeManager.applications = { config, pkgs, ... }: {
      home.packages = packagesFor pkgs;

      # Flatpak media applications
      services.flatpak.packages = [
        "org.gnome.Decibels" # Audio player
        "com.plexamp.Plexamp" # Music player
        "tv.plex.PlexDesktop" # Media center
        # "com.obsproject.Studio" # Video recording/streaming
        # "com.obsproject.Studio.Plugin.OBSVkCapture" # OBS plugin
        "be.alexandervanhee.gradia" # image editor
        "org.kde.iconexplorer" # Icon Explorer
        "org.upscayl.Upscayl"
      ];

      services.flatpak.overrides."org.upscayl.Upscayl".Context.filesystems = [
        config.xdg.userDirs.download
      ];
    };
  };
}
