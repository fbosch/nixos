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
            { config, pkgs, surgeSystem, ... }:
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

              systemd.user.services.screenshot-cleanup = {
                Unit = {
                  Description = "Move screenshots older than seven days to the trash";
                };
                Service = {
                  Type = "oneshot";
                  Nice = 19;
                  CPUWeight = 10;
                  IOSchedulingClass = "idle";
                  IOWeight = 10;
                  ExecStart = "${pkgs.writeShellScript "screenshot-cleanup" ''
                    set -euo pipefail
                    screenshot_dir="${config.home.homeDirectory}/Pictures/screenshots"

                    if [ ! -d "$screenshot_dir" ]; then
                      exit 0
                    fi

                    while IFS= read -r -d "" image; do
                      ${pkgs.glib}/bin/gio trash "$image"
                    done < <(
                      ${pkgs.findutils}/bin/find "$screenshot_dir" \
                        -xdev \
                        -type f \
                        -regextype posix-extended \
                        -iregex '.*\.(avif|bmp|gif|heic|heif|jpe?g|jxl|png|svg|tiff?|webp)$' \
                        -mmin +10080 \
                        -print0
                    )
                  ''}";
                };
              };

              systemd.user.timers.screenshot-cleanup = {
                Unit = {
                  Description = "Daily screenshot cleanup timer";
                };
                Timer = {
                  OnCalendar = "daily";
                  Persistent = true;
                };
                Install.WantedBy = [ "timers.target" ];
              };
            }
          )
        ];
      };
    };
}
