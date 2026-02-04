{ config, ... }:
{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      gh-mcp = pkgs.stdenvNoCC.mkDerivation {
        pname = "gh-mcp";
        version = "1.16.0";
        src = pkgs.fetchurl {
          url = "https://github.com/shuymn/gh-mcp/releases/download/v1.16.0/linux-amd64";
          hash = "sha256-51h6H990TFZlv5G22JPLwAS7mPObPdQqMbM83cZVOhg=";
        };
        dontUnpack = true;
        installPhase = ''
          install -Dm755 "$src" "$out/bin/gh-mcp"
          install -Dm755 "$src" "$out/share/gh/extensions/gh-mcp/gh-mcp"
        '';
      };
    in
    {
      home.packages = with pkgs; [
        # git-credential-manager
        lazygit
        delta
        difftastic
        gitui
      ];

      programs.git = {
        enable = true;
        settings.credential = {
          helper = "manager";
          "https://github.com".username = config.flake.meta.user.github.username;
          credentialStore = "secretservice";
        };
      };

      programs.gh = {
        enable = true;
        extensions = with pkgs; [
          gh-mcp
          gh-markdown-preview
        ];
      };
    };
}
