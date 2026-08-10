{ config, lib, ... }:
let
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      lazygit
      delta
      difftastic
      diffnav
      gitui
    ];
  };
  mkGitPlatformConfig =
    pkgs: isCorporateHost:
    let
      credentialHelper =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "/usr/bin/git-credential-osxkeychain"
        else
          "${pkgs.gitFull}/bin/git-credential-libsecret";
    in
    ''
      [credential]
        helper = ${credentialHelper}
    ''
    + lib.optionalString (!isCorporateHost) ''
      [credential "https://github.com"]
        username = ${config.flake.meta.user.github.username}
    '';
  homeManagerDevelopment =
    { pkgs
    , hostMeta
    , ...
    }:
    {
      programs.git = {
        enable = true;
        package = if pkgs.stdenv.hostPlatform.isLinux then pkgs.gitFull else pkgs.git;
      };

      xdg.configFile."nix/git/config".text = mkGitPlatformConfig pkgs (hostMeta.corporate or false);

      programs.gh = {
        enable = true;
        extensions = with pkgs; [
          pkgs.local.gh-mcp
          gh-markdown-preview
          gh-dash
        ];
      };
    };
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
    homeManager.development = homeManagerDevelopment;
  };

  perSystem =
    { lib, pkgs, ... }:
    let
      configFor =
        system:
        mkGitPlatformConfig
          (pkgs // {
            stdenv = pkgs.stdenv // {
              hostPlatform = lib.systems.elaborate system;
            };
          })
          false;
    in
    {
      nix-unit.tests.gitCredentialOwnership = {
        testGeneratesPlatformCredentialConfig = {
          expr = [
            (configFor "aarch64-darwin")
            (configFor "x86_64-linux")
          ];
          expected = [
            ''
              [credential]
                helper = /usr/bin/git-credential-osxkeychain
              [credential "https://github.com"]
                username = ${config.flake.meta.user.github.username}
            ''
            ''
              [credential]
                helper = ${pkgs.gitFull}/bin/git-credential-libsecret
              [credential "https://github.com"]
                username = ${config.flake.meta.user.github.username}
            ''
          ];
        };
      };
    };
}
