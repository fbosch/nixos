{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        # File previewer for Nemo file manager
        sushi
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # Video players
        vlc

        # Image viewers
        loupe # GNOME image viewer
        swayimg # Wayland image viewer

        # Audio control
        pavucontrol # PulseAudio volume control

        # Media web apps
        local.chromium-youtubemusic # YouTube Music
        local.chromium-synologyphotos # Synology Photos
      ];

      # Flatpak media applications
      services.flatpak.packages = [
        "org.gnome.Decibels" # Audio player
        "com.plexamp.Plexamp" # Music player
        "tv.plex.PlexDesktop" # Media center
        "com.obsproject.Studio" # Video recording/streaming
        "com.obsproject.Studio.Plugin.OBSVkCapture" # OBS plugin
        "be.alexandervanhee.gradia" # image editor
      ];
    };
}
