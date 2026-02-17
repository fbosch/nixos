{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    {
      environment.etc."firejail/helium.profile".source = pkgs.replaceVars ./helium.profile {
        chromiumProfile = "${pkgs.firejail}/etc/firejail/chromium.profile";
      };

      programs.firejail = {
        enable = true;
        wrappedBinaries =
          let
            chromiumPackages = lib.filterAttrs (name: _: lib.hasPrefix "chromium-" name) pkgs.local;

            browserPackages = chromiumPackages;
          in
          (lib.mapAttrs'
            (name: package: {
              inherit name;
              value = {
                executable = "${package}/bin/${name}";
                profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
                desktop = "${package}/share/applications/${name}.desktop";
              };
            })
            browserPackages)
          // {
            helium = {
              executable = "${pkgs.local.helium-browser}/bin/helium-browser";
              profile = "/etc/firejail/helium.profile";
              desktop = "${pkgs.local.helium-browser}/share/applications/helium-browser.desktop";
            };

            vlc = {
              executable = "${pkgs.vlc}/bin/vlc";
              profile = "${pkgs.firejail}/etc/firejail/vlc.profile";
              desktop = "${pkgs.vlc}/share/applications/vlc.desktop";
            };
          };
      };
    };
}
