let
  packagesFor =
    pkgs:
    (with pkgs; [
      fnm
      bun
      nodejs_24
      yarn
      typescript-go
      prettier
      eslint
      npm-check-updates
      prettierd
      playwright-test
    ])
    ++ [ (pkgs.local.pnpm or pkgs.pnpm) ];
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
