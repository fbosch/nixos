{ lib }:
let
  sshSource = builtins.readFile ../../modules/shell/ssh.nix;
  serverSource = builtins.readFile ../../modules/hosts/rvn-srv/default.nix;
  serverSystemSource = builtins.readFile ../../modules/hosts/rvn-srv/platform/system.nix;
  gnomeSource = builtins.readFile ../../modules/desktop/gnome/default.nix;
  dotfilesSource = builtins.readFile ../../modules/dotfiles.nix;
  gitSource = builtins.readFile ../../modules/development/git.nix;
  surgeSource = builtins.readFile ../../modules/applications/surge.nix;
in
{
  ssh = {
    testHomeManagerDoesNotOwnAuthorizedKeys = {
      expr = lib.hasInfix ".ssh/authorized_keys" sshSource;
      expected = false;
    };

    testServerSelectsGpgAgent = {
      expr = lib.hasInfix ''sshAgent = "gpg";'' serverSource;
      expected = true;
    };

    testGpgAgentFollowsHostMetadata = {
      expr = lib.hasInfix ''enableSSHSupport = hostMeta.sshAgent == "gpg";'' serverSystemSource;
      expected = true;
    };

    testHomeManagerAgentFollowsHostMetadata = {
      expr = lib.hasInfix ''services.ssh-agent.enable = sshAgent == "ssh-agent";'' sshSource;
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

  git = {
    testPlatformCredentialHelpersAreExplicit = {
      expr = lib.all (helper: lib.hasInfix helper gitSource) [
        "/usr/bin/git-credential-osxkeychain"
        "git-credential-libsecret"
      ];
      expected = true;
    };

    testLegacyCredentialManagerIsAbsent = {
      expr = lib.any (setting: lib.hasInfix setting gitSource) [
        ''helper = "manager"''
        "credentialStore"
      ];
      expected = false;
    };

    testGeneratedPlatformIncludeHasOneHelper = {
      expr = lib.hasInfix ''xdg.configFile."nix/git/config".text = gitPlatformConfig;'' gitSource;
      expected = true;
    };
  };

  surge = {
    testServiceUsesConfiguredPackage = {
      expr = lib.hasInfix "ExecStart = \"\${lib.getExe cfg.package} \${serverArgs}\";" surgeSource;
      expected = true;
    };

    testAppArmorUsesConfiguredPackage = {
      expr = lib.hasInfix "\${lib.getExe cfg.package} flags=(attach_disconnected)" surgeSource;
      expected = true;
    };

    testAppArmorAllowsOnlyConfiguredOutputRoot = {
      expr = lib.hasInfix "owner \${outputDir}/** rwk," surgeSource;
      expected = true;
    };

    testAppArmorHasNoBroadHomeOrMountWrites = {
      expr = lib.any (rule: lib.hasInfix rule surgeSource) [
        "owner @{HOME}/** rw,"
        "owner /mnt/** rw,"
      ];
      expected = false;
    };

    testAppArmorDeniesSensitivePaths = {
      expr = lib.all (rule: lib.hasInfix rule surgeSource) [
        "deny @{HOME}/.ssh/** rw,"
        "deny @{HOME}/.gnupg/** rw,"
      ];
      expected = true;
    };
  };
}
