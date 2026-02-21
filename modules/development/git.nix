{ config, ... }:
{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      gh-mcp-asset =
        if pkgs.stdenv.hostPlatform.isDarwin then
          if pkgs.stdenv.hostPlatform.isAarch64 then
            {
              name = "darwin-arm64";
              hash = "sha256-bxXppEIErs95MQq0vMmda8g7qUQ577LrcrVGif5pxBI=";
            }
          else if pkgs.stdenv.hostPlatform.isx86_64 then
            {
              name = "darwin-amd64";
              hash = "sha256-iqVWCOFq83JspKteqTq1NJA+g7SBe4OO07rOQ9YTKo4=";
            }
          else
            throw "gh-mcp: unsupported Darwin architecture ${pkgs.stdenv.hostPlatform.system}"
        else if pkgs.stdenv.hostPlatform.isLinux then
          if pkgs.stdenv.hostPlatform.isAarch64 then
            {
              name = "linux-arm64";
              hash = "sha256-l8xiBBzOvCncRWMf93TOuL4gpY4SKqRSjb9E9IpnlR4=";
            }
          else if pkgs.stdenv.hostPlatform.isx86_64 then
            {
              name = "linux-amd64";
              hash = "sha256-HG0t2r6K7TVSXZpsjxlHgEIRi1fXBjX6eTNXqlkpg+M=";
            }
          else
            throw "gh-mcp: unsupported Linux architecture ${pkgs.stdenv.hostPlatform.system}"
        else
          throw "gh-mcp: unsupported platform ${pkgs.stdenv.hostPlatform.system}";

      gh-mcp = pkgs.stdenvNoCC.mkDerivation {
        pname = "gh-mcp";
        version = "2.0.1";
        src = pkgs.fetchurl {
          url = "https://github.com/shuymn/gh-mcp/releases/download/v${gh-mcp.version}/${gh-mcp-asset.name}";
          inherit (gh-mcp-asset) hash;
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
          gh-dash
        ];
      };
    };
}
