let
  mkDiffnav =
    pkgs:
    pkgs.diffnav.overrideAttrs (previous: {
      patches = (previous.patches or [ ]) ++ [ ./zenwritten-dark.patch ];
      doCheck = true;
    });
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = [ (mkDiffnav pkgs) ];
  };
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
  };

  perSystem =
    { pkgs, ... }:
    let
      diffnav = mkDiffnav pkgs;
    in
    {
      packages.diffnav = diffnav;
      checks.diffnav = diffnav;
    };
}
