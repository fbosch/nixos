{ config, ... }:
let
  packagesFor =
    pkgs: with pkgs; [
      lazygit
      delta
      difftastic
      diffnav
      gitui
    ];
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = packagesFor pkgs;
  };
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
    homeManager.development =
      { pkgs
      , lib
      , hostMeta
      , ...
      }:
      let
        isCorporateHost = hostMeta.corporate or false;
        gitCredentialHelper =
          if pkgs.stdenv.hostPlatform.isDarwin then
            "/usr/bin/git-credential-osxkeychain"
          else
            "${pkgs.gitFull}/bin/git-credential-libsecret";
        gitPlatformConfig = ''
          [credential]
            helper = ${gitCredentialHelper}
        ''
        + lib.optionalString (!isCorporateHost) ''
          [credential "https://github.com"]
            username = ${config.flake.meta.user.github.username}
        '';
      in
      {
        home.packages = packagesFor pkgs;

        programs.git = {
          enable = true;
          package = if pkgs.stdenv.hostPlatform.isLinux then pkgs.gitFull else pkgs.git;
        };

        xdg.configFile."nix/git/config".text = gitPlatformConfig;

        programs.gh = {
          enable = true;
          extensions = with pkgs; [
            pkgs.local.gh-mcp
            gh-markdown-preview
            gh-dash
          ];
        };
      };
  };

  perSystem =
    { lib, ... }:
    let
      gitSource = builtins.readFile ./git.nix;
    in
    {
      nix-unit.tests.gitCredentialOwnership = {
        testPlatformCredentialHelpersAreExplicit = {
          expr = lib.all (helper: lib.hasInfix helper gitSource) [
            ("/usr/bin/git-credential-" + "osxkeychain")
            ("git-credential-" + "libsecret")
          ];
          expected = true;
        };
        testLegacyCredentialManagerIsAbsent = {
          expr = lib.any (setting: lib.hasInfix setting gitSource) [
            (''helper = "'' + ''manager"'')
            ("credential" + "Store")
          ];
          expected = false;
        };
        testGeneratedPlatformIncludeHasOneHelper = {
          expr = lib.hasInfix (''xdg.configFile."nix/git/config".text = '' + "gitPlatformConfig;") gitSource;
          expected = true;
        };
      };
    };
}
