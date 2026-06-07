{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        astro-language-server
        lua-language-server
        marksman
        tailwindcss-language-server
        typescript-language-server
        vscode-langservers-extracted
      ];
    };
}
