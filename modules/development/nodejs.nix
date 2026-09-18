let
  systemPackages =
    { pkgs, ... }:
    let
      playwrightTest =
        if pkgs.stdenv.hostPlatform.isLinux then
          let
            # shortcut: Patch nixpkgs' WebKit browser until its dependency list includes libmanette.
            callPackage =
              path: args:
              let
                package = pkgs.callPackage path args;
              in
              if pkgs.lib.hasSuffix "/playwright/webkit.nix" (toString path) then
                package.overrideAttrs
                  (previous: {
                    buildInputs = previous.buildInputs ++ [ pkgs.libmanette ];
                  })
              else
                package;
            driver =
              pkgs.callPackage "${pkgs.path}/pkgs/development/web/playwright/driver.nix" {
                inherit callPackage;
              };
          in
          driver.playwright-test
        else
          pkgs.playwright-test;
    in
    {
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
          playwrightTest
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
