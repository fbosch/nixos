let
  packagesFor =
    pkgs: with pkgs; [
      astro-language-server
      lua-language-server
      marksman
      tailwindcss-language-server
      vscode-langservers-extracted
    ];
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = packagesFor pkgs;
  };
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
  };
}
