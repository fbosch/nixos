{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      # Flatpak communication applications
      services.flatpak.packages = [
        "com.discordapp.Discord" # Messaging and voice chat
        "org.signal.Signal" # Secure messaging
      ];

      services.flatpak.overrides."com.discordapp.Discord" = {
        Context = {
          sockets = [
            "wayland"
            "x11"
            "pulseaudio"
          ];
          shared = [
            "network"
            "ipc"
          ];
          devices = [ "all" ];
          filesystems = [
            "xdg-downloads"
            "xdg-videos"
            "xdg-pictures"
          ];
        };
        Environment = {
          # Enable Wayland support
          NIXOS_OZONE_WL = "1";
        };
      };

      # MIME type handlers for communication protocols
      xdg.mimeApps.defaultApplications = {
        "x-scheme-handler/discord" = [ "com.discordapp.Discord.desktop" ];
        "x-scheme-handler/signal" = [ "org.signal.Signal.desktop" ];
      };
    };
}
