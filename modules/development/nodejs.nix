{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home = {
        packages = with pkgs; [
          fnm
          bun
          nodejs_24
          local.pnpm
          yarn
          typescript
          prettier
          eslint
          npm-check-updates
          prettierd
          playwright-test
        ];
      };
    };
}
