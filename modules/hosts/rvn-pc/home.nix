{ inputs, config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos."hosts/rvn-pc/home" =
    { config, ... }:
    let
      surgeSystem = {
        inherit (config.services.surge) package outputDir;
      };
    in
    {
      home-manager = {
        extraSpecialArgs = { inherit surgeSystem; };

        users.${flakeConfig.flake.meta.user.username}.imports =
          flakeConfig.flake.lib.resolveHm [
            # Desktop preset (includes users, dotfiles, fonts, security, desktop, applications, development, shell)
            "presets/desktop"
            "applications/surge"
            "windows"
            "worktrunk"
            "virtualization/podman"

            # Shared modules with Home Manager components
            "secrets"
          ]
          ++ [
            # External Home Manager modules
            inputs.flatpaks.homeManagerModules.nix-flatpak

            # User directory configuration
            (
              { config, surgeSystem, ... }:
              {
                xdg.userDirs = {
                  enable = true;
                  setSessionVariables = true;
                  download = surgeSystem.outputDir;
                };

                home.file."Downloads".source = config.lib.file.mkOutOfStoreSymlink config.xdg.userDirs.download;

                xdg.configFile."gtk-3.0/bookmarks".text = ''
                  file://${config.xdg.userDirs.download} Downloads
                  file://${config.home.homeDirectory}/Pictures Pictures
                  file:///mnt/games Games
                  file://${config.home.homeDirectory}/Projects Projects
                '';

                services.surge = {
                  inherit (surgeSystem) package outputDir;
                  autostart = true;
                  settings = {
                    general.default_download_dir = surgeSystem.outputDir;
                    network.proxy_url = "http://192.168.1.46:8889";
                  };
                };
              }
            )
          ];
      };
    };
}
