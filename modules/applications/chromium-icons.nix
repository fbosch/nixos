{
  flake.modules.nixos.chromium-icons = { config, lib, pkgs, ... }: {
    # Ensure icons are available system-wide for Waybar
    environment.pathsToLink = [ "/share/icons" ];

    # Create symlinks to chromium app icons using mkOutOfStoreSymlink pattern
    environment.systemPackages = with pkgs; [
      (runCommand "chromium-app-icons" { } ''
        mkdir -p $out/share/icons/hicolor/512x512/apps

        # Symlink each chromium app icon to system location
        ln -s ${pkgs.local.chromium-chatgpt}/share/icons/hicolor/512x512/apps/ChatGPT.png $out/share/icons/hicolor/512x512/apps/
        ln -s ${pkgs.local.chromium-realforce}/share/icons/hicolor/512x512/apps/Realforce.png $out/share/icons/hicolor/512x512/apps/
        ln -s ${pkgs.local.chromium-youtubemusic}/share/icons/hicolor/512x512/apps/YouTube\ Music.png $out/share/icons/hicolor/512x512/apps/
        ln -s ${pkgs.local.chromium-notion}/share/icons/hicolor/512x512/apps/Notion.png $out/share/icons/hicolor/512x512/apps/
        ln -s ${pkgs.local.chromium-protonmail}/share/icons/hicolor/512x512/apps/Proton\ Mail.png $out/share/icons/hicolor/512x512/apps/
        ln -s ${pkgs.local.chromium-protoncalendar}/share/icons/hicolor/512x512/apps/Proton\ Calendar.png $out/share/icons/hicolor/512x512/apps/
        ln -s ${pkgs.local.chromium-synologyphotos}/share/icons/hicolor/512x512/apps/Synology\ Photos.png $out/share/icons/hicolor/512x512/apps/
      '')
    ];
  };
}
