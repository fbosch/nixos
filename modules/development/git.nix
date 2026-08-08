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
}
