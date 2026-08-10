let
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      astro-language-server
      lua-language-server
      marksman
      tailwindcss-language-server
      vscode-langservers-extracted
    ];
  };
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
  };
}
