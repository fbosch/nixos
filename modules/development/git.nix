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
              hash = "sha256-mtnWK1/RDT+/BRWoXS6mVWH0i6cs5gkhvyPDiSuf07s=";
            }
          else if pkgs.stdenv.hostPlatform.isx86_64 then
            {
              name = "darwin-amd64";
              hash = "sha256-YFLD1YzuIVITXz6+5/kgdFzyTgHvogsFfTFll7dLirA=";
            }
          else
            throw "gh-mcp: unsupported Darwin architecture ${pkgs.stdenv.hostPlatform.system}"
        else if pkgs.stdenv.hostPlatform.isLinux then
          if pkgs.stdenv.hostPlatform.isAarch64 then
            {
              name = "linux-arm64";
              hash = "sha256-yoDYniCKYfwqMWFPCv8iEDcqBmCu5tKxKjCQcmW4G90=";
            }
          else if pkgs.stdenv.hostPlatform.isx86_64 then
            {
              name = "linux-amd64";
              hash = "sha256-51h6H990TFZlv5G22JPLwAS7mPObPdQqMbM83cZVOhg=";
            }
          else
            throw "gh-mcp: unsupported Linux architecture ${pkgs.stdenv.hostPlatform.system}"
        else
          throw "gh-mcp: unsupported platform ${pkgs.stdenv.hostPlatform.system}";

      gh-mcp = pkgs.stdenvNoCC.mkDerivation {
        pname = "gh-mcp";
        version = "1.16.0";
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
        ];
      };
    };
}
