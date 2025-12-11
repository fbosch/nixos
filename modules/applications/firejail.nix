{
  flake.modules.nixos.applications = { pkgs, lib, ... }: {
    programs.firejail = {
      enable = true;
      wrappedBinaries =
        let
          # Get all chromium packages from pkgs.local
          chromiumPackages =
            lib.filterAttrs (name: _: lib.hasPrefix "chromium-" name) pkgs.local;
        in
        lib.mapAttrs'
          (name: package: {
            inherit name;
            value = {
              executable = "${package}/bin/${name}";
              profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
              desktop = "${package}/share/applications/${name}.desktop";
            };
          })
          chromiumPackages;
    };
  };
}
