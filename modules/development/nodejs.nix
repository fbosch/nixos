let
  systemPackages = { pkgs, ... }: {
    environment.systemPackages =
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
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
  };
}
