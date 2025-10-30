{
  flake.modules.homeManager.development = { pkgs, ... }: {
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
    ];

    home.sessionVariables = {
      PNPM_HOME = "$HOME/.local/share/pnpm";
    };

    home.sessionPath = [
      "$HOME/.local/share/pnpm"
    ];
  };
}
