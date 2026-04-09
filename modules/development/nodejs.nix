{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home = {
        packages = with pkgs; [
          fnm
          bun
          nodejs_24
          pnpm
          yarn
          typescript
          prettier
          eslint
          npm-check-updates
          typescript-language-server
          prettierd
          playwright-test
        ];
      };
    };
}
