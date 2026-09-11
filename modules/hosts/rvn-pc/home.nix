{ config, ... }:
let
  flakeConfig = config;
  obsidianVault = "/mnt/nas/FrederikDocs/Obsidian/Vault";
  obsidianVaultId = builtins.substring 0 16 (builtins.hashString "sha256" obsidianVault);
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

        users.${flakeConfig.flake.meta.user.username}.imports = [
          (
            { config, surgeSystem, ... }:
            {
              xdg.userDirs = {
                enable = true;
                setSessionVariables = true;
                download = surgeSystem.outputDir;
              };

              # Flatpak keeps Obsidian's global vault registry in its sandbox config.
              home.file.".var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json" = {
                force = true;
                text = builtins.toJSON {
                  vaults = {
                    ${obsidianVaultId} = {
                      path = obsidianVault;
                      open = true;
                      ts = 0;
                    };
                  };
                };
              };
              services.flatpak.overrides."md.obsidian.Obsidian".Context.filesystems = [
                "${obsidianVault}:rw"
              ];

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
