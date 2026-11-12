{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = [
      (pkgs.waybar.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./patches/waybar-module-hover-commands.patch
          ./patches/waybar-slide-visibility.patch
          ./patches/waybar-taskbar-truncate.patch
          ./patches/waybar-taskbar-icon-resolution.patch
        ];
        postPatch = (old.postPatch or "") + ''

          substituteInPlace src/modules/sni/item.cpp \
            --replace-fail \
            '} else if (name == "IconName") {' \
            '} else if (name == "IconName" && IconManager::instance().getIconForApp(id).empty()) {' \
            --replace-fail \
            '} else if (name == "IconPixmap") {' \
            '} else if (name == "IconPixmap" && IconManager::instance().getIconForApp(id).empty()) {'
        '';
      }))
    ];
  };
}
