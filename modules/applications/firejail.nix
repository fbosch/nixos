{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    {
      programs.firejail = {
        enable = true;
        wrappedBinaries =
          let
            chromiumPackages = lib.filterAttrs (name: _: lib.hasPrefix "chromium-" name) pkgs.local;

            browserPackages = chromiumPackages;
          in
          lib.mkMerge [
            (lib.mapAttrs' (name: package: {
              inherit name;
              value = {
                executable = "${package}/bin/${name}";
                profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
                desktop = "${package}/share/applications/${name}.desktop";
              };
            }) browserPackages)
            {
              vlc = {
                executable = "${pkgs.vlc}/bin/vlc";
                profile = "${pkgs.firejail}/etc/firejail/vlc.profile";
                desktop = "${pkgs.vlc}/share/applications/vlc.desktop";
              };
            }
          ];
      };
    };
}
