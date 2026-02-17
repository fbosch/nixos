{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    {
      environment.etc."firejail/helium.profile".text = ''
        include ${pkgs.firejail}/etc/firejail/chromium.profile

        # Allow user GTK theme + settings
        whitelist ''${HOME}/.themes
        whitelist ''${HOME}/.local/share/themes
        whitelist ''${HOME}/.config/gtk-3.0
        whitelist ''${HOME}/.config/gtk-4.0
        whitelist ''${HOME}/.gtkrc-2.0
      '';

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
          };
      };
    };
}
