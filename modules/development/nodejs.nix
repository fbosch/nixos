{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home = {
        packages =
          (with pkgs; [
            fnm
            bun
            nodejs_24
            yarn
            typescript
            prettier
            eslint
            npm-check-updates
            prettierd
            playwright-test
          ])
          ++ [ (pkgs.local.pnpm or pkgs.pnpm) ];
      };
    };
}
