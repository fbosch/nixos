{ lib, serverSshOwnership }:
let
  modulesRoot = ../../modules;
  nixFilesIn =
    directory:
    let
      entries = builtins.readDir directory;
    in
    lib.concatMap
      (
        name:
        let
          path = directory + "/${name}";
          type = entries.${name};
        in
        if type == "directory" then
          nixFilesIn path
        else
          lib.optional (type == "regular" && lib.hasSuffix ".nix" name) path
      )
      (builtins.attrNames entries);
  literalHomePackageOwners = map (path: lib.removePrefix "${toString modulesRoot}/" (toString path)) (
    lib.filter (path: lib.hasInfix "home.packages" (builtins.readFile path)) (nixFilesIn modulesRoot)
  );
  gnomeSource = builtins.readFile ../../modules/desktop/gnome/default.nix;
in
{
  ssh.testServerSelectsSingleAgentOwner = {
    expr = serverSshOwnership;
    expected = {
      selectedOwner = "gpg";
      gpgSshSupport = true;
      homeManagerSshAgent = false;
    };
  };

  gtk = {
    testHomeManagerOwnsGtkSettings = {
      expr = lib.all (path: lib.hasInfix path gnomeSource) [
        ''"gtk-3.0/settings.ini"''
        ''"gtk-4.0/settings.ini"''
        ''"gtk-4.0/gtk.css"''
      ];
      expected = true;
    };

  };

  # This inventories explicit home.packages declarations. Home Manager program
  # modules may install packages indirectly and require semantic review instead.
  packageOwnership.testOnlyApprovedLiteralHomePackageOwnersRemain = {
    expr = lib.sort builtins.lessThan literalHomePackageOwners;
    expected = [
      "applications/gaming/steam/theme.nix"
      "applications/windows.nix"
      "desktop/update-checker.nix"
      "dotfiles.nix"
    ];
  };
}
