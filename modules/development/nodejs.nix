{
  flake.modules.homeManager.development = { pkgs, ... }: {
    home.packages = with pkgs; [
      fnm
      nodejs_22
      nodePackages.pnpm
      nodePackages.yarn
      nodePackages.typescript
      nodePackages.typescript-language-server
      nodePackages.vscode-langservers-extracted
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
