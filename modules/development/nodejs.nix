{
  flake.modules.homeManager.development = { pkgs, lib, ... }:
    let
      npmGlobalPackages = pkgs.buildNpmGlobalPackage [
        {
          package = "pokemonshow@4.0.0";
          hash = "sha256-9+HE/XKtLA2cn0/bqMA4H6gE2Sz+N7nOiA27G2ih2f0=";
        }
        {
          package = "swpm@2.6.0";
          hash = "sha256-ZE722zmYt0trh9kP4eq2BkOKssbgz6wsHFW1930oM5Q=";
        }
      ];
    in
    {
      home = {
        packages = with pkgs; [
          fnm
          nodejs_22
          bun
          nodePackages.pnpm
          nodePackages.yarn
          nodePackages.typescript
          nodePackages.prettier
          nodePackages.eslint
          nodePackages.vercel
          nodePackages.npm-check-updates
        ] ++ npmGlobalPackages;

        sessionVariables = {
          PNPM_HOME = "$HOME/.local/share/pnpm";
        };

        sessionPath = [
          "$HOME/.local/share/pnpm"
        ];
      };
    };
}
