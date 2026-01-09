{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    {
      programs.firejail = {
        enable = true;
        wrappedBinaries =
          let
            # Get all chromium packages from pkgs.local except chromium-realforce
            # (realforce needs USB/HID access which conflicts with firejail sandboxing)
            chromiumPackages = lib.filterAttrs
              (name: _: lib.hasPrefix "chromium-" name && name != "chromium-realforce")
              pkgs.local;
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
