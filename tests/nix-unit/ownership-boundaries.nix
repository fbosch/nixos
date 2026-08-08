{ lib }:
let
  serverSource = builtins.readFile ../../modules/hosts/rvn-srv/default.nix;
  serverSystemSource = builtins.readFile ../../modules/hosts/rvn-srv/platform/system.nix;
  gnomeSource = builtins.readFile ../../modules/desktop/gnome/default.nix;
  dotfilesSource = builtins.readFile ../../modules/dotfiles.nix;
in
{
  ssh = {
    testServerSelectsGpgAgent = {
      expr = lib.hasInfix ''sshAgent = "gpg";'' serverSource;
      expected = true;
    };

    testGpgAgentFollowsHostMetadata = {
      expr = lib.hasInfix ''enableSSHSupport = hostMeta.sshAgent == "gpg";'' serverSystemSource;
      expected = true;
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

    testDotfilesActivationDoesNotOwnGtk = {
      expr = lib.hasInfix ".config/gtk-" dotfilesSource;
      expected = false;
    };

    testNoPermanentGtkMigrationCleanup = {
      expr = lib.hasInfix "removeStaleGtkLinks" gnomeSource;
      expected = false;
    };
  };

}
