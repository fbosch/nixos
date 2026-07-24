{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # File previewer for Nemo file manager
        sushi
        media-downloader
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs
    , ...
    }:
    let
      proxyHost = flakeConfig.flake.lib.hostMeta "rvn-srv";
    in
    {
      home.packages = with pkgs; [
        # Image viewers
        loupe # GNOME image viewer

        # Media web apps
        local."webapp/youtubemusic" # YouTube Music
        local."webapp/synologyphotos" # Synology Photos
      ];

      # Flatpak media applications
      services.flatpak.packages = [
        "org.gnome.Decibels" # Audio player
        "com.plexamp.Plexamp" # Music player
        "tv.plex.PlexDesktop" # Media center
        # "com.obsproject.Studio" # Video recording/streaming
        # "com.obsproject.Studio.Plugin.OBSVkCapture" # OBS plugin
        "be.alexandervanhee.gradia" # image editor
        "org.kde.iconexplorer" # Icon Explorer
      ];

      xdg.dataFile."media-downloader/settings/settings.ini".text = ''
        [General]
        ProxySettingsType=Manual
        ProxySettingsCustomSource=http://${proxyHost.local}:8889
      '';
    };
}
