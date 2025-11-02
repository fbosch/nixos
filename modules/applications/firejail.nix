{
  flake.modules.nixos.applications = { pkgs, ... }: {
    programs.firejail = {
      enable = true;
      wrappedBinaries = {
        chromium-protonmail = {
          executable =
            "${pkgs.local.chromium-protonmail}/bin/chromium-protonmail";
          profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
        };
        chromium-protoncalendar = {
          executable =
            "${pkgs.local.chromium-protoncalendar}/bin/chromium-protoncalendar";
          profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
        };
        chromium-youtubemusic = {
          executable =
            "${pkgs.local.chromium-youtubemusic}/bin/chromium-youtubemusic";
          profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
        };
      };
    };
  };
}
