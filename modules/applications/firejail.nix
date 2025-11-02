{
  flake.modules.nixos.applications = { pkgs, ... }: {
    programs.firejail = {
      enable = true;
      wrappedBinaries = {
        chromium-protonmail = {
          executable =
            "${pkgs.local.chromium-protonmail}/bin/chromium-protonmail";
          profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
          desktop = "${pkgs.local.chromium-protonmail}/share/applications/chromium-protonmail.desktop";
        };
        chromium-protoncalendar = {
          executable =
            "${pkgs.local.chromium-protoncalendar}/bin/chromium-protoncalendar";
          profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
          desktop = "${pkgs.local.chromium-protoncalendar}/share/applications/chromium-protoncalendar.desktop";
        };
        chromium-youtubemusic = {
          executable =
            "${pkgs.local.chromium-youtubemusic}/bin/chromium-youtubemusic";
          profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
          desktop = "${pkgs.local.chromium-youtubemusic}/share/applications/chromium-youtubemusic.desktop";
        };
      };
    };
  };
}
