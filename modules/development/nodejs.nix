{
  flake.modules.homeManager.development = { pkgs, ... }: 
  let
    npmGlobalPackages = pkgs.buildNpmGlobalPackage [
        {
          package = "pokemonshow@4.0.0";
          hash = "sha256-9+HE/XKtLA2cn0/bqMA4H6gE2Sz+N7nOiA27G2ih2f0=";
        }
    ];
  in
  {
    home.packages = with pkgs; [
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

    home.sessionVariables = {
      PNPM_HOME = "$HOME/.local/share/pnpm";
    };

    home.sessionPath = [
      "$HOME/.local/share/pnpm"
    ];
  };
}
