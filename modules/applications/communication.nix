{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      # Flatpak communication applications
      # Note: Flatpak overrides are centralized in flatpak.nix
      services.flatpak.packages = [
        "com.discordapp.Discord" # Messaging and voice chat
        "org.signal.Signal" # Secure messaging
      ];

      # MIME type handlers for communication protocols
      xdg.mimeApps.defaultApplications = {
        "x-scheme-handler/discord" = [ "com.discordapp.Discord.desktop" ];
        "x-scheme-handler/signal" = [ "org.signal.Signal.desktop" ];
      };
    };
}
