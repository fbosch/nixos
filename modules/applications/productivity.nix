{ inputs, ... }:
{
  flake.modules.homeManager.applications =
    { pkgs, lib, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      handyPackage = inputs.handy.packages.${system}.default;
    in
    {
      home.packages =
        (with pkgs; [
          gimp
          pkgs.local.chromium-chatgpt
          pkgs.local.chromium-notion
          pkgs.local.chromium-protonmail
          pkgs.local.chromium-protoncalendar
          pkgs.local.chromium-linear
          pkgs.local.chromium-figma
        ])
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          handyPackage
        ];

      services.flatpak.packages = [ "md.obsidian.Obsidian" ];
    };
}
