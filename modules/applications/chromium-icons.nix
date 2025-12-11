{
  flake.modules.nixos.chromium-icons = { config, lib, pkgs, ... }: {
    # Install chromium app icons system-wide for Waybar compatibility
    environment.systemPackages = with pkgs; [
      # Create a package that installs all chromium app icons
      (runCommand "chromium-app-icons" { } ''
        mkdir -p $out/share/icons/hicolor/512x512/apps

        # Copy icons from all chromium packages
        ${lib.optionalString (lib.hasAttrByPath ["local" "chromium-chatgpt"] pkgs.local) ''
          cp ${pkgs.local.chromium-chatgpt}/share/icons/hicolor/512x512/apps/ChatGPT.png $out/share/icons/hicolor/512x512/apps/ 2>/dev/null || true
        ''}

        ${lib.optionalString (lib.hasAttrByPath ["local" "chromium-realforce"] pkgs.local) ''
          cp ${pkgs.local.chromium-realforce}/share/icons/hicolor/512x512/apps/Realforce.png $out/share/icons/hicolor/512x512/apps/ 2>/dev/null || true
        ''}

        ${lib.optionalString (lib.hasAttrByPath ["local" "chromium-youtubemusic"] pkgs.local) ''
          cp ${pkgs.local.chromium-youtubemusic}/share/icons/hicolor/512x512/apps/YouTube\ Music.png $out/share/icons/hicolor/512x512/apps/ 2>/dev/null || true
        ''}

        ${lib.optionalString (lib.hasAttrByPath ["local" "chromium-notion"] pkgs.local) ''
          cp ${pkgs.local.chromium-notion}/share/icons/hicolor/512x512/apps/Notion.png $out/share/icons/hicolor/512x512/apps/ 2>/dev/null || true
        ''}

        ${lib.optionalString (lib.hasAttrByPath ["local" "chromium-protonmail"] pkgs.local) ''
          cp ${pkgs.local.chromium-protonmail}/share/icons/hicolor/512x512/apps/Proton\ Mail.png $out/share/icons/hicolor/512x512/apps/ 2>/dev/null || true
        ''}

        ${lib.optionalString (lib.hasAttrByPath ["local" "chromium-protoncalendar"] pkgs.local) ''
          cp ${pkgs.local.chromium-protoncalendar}/share/icons/hicolor/512x512/apps/Proton\ Calendar.png $out/share/icons/hicolor/512x512/apps/ 2>/dev/null || true
        ''}

        ${lib.optionalString (lib.hasAttrByPath ["local" "chromium-synologyphotos"] pkgs.local) ''
          cp ${pkgs.local.chromium-synologyphotos}/share/icons/hicolor/512x512/apps/Synology\ Photos.png $out/share/icons/hicolor/512x512/apps/ 2>/dev/null || true
        ''}
      '')
    ];
  };
}
