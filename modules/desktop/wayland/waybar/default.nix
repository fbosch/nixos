{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = [
      (pkgs.waybar.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./patches/waybar-slide-visibility.patch
          ./patches/waybar-taskbar-truncate.patch
        ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/modules/hyprland/workspace.cpp \
            --replace-fail \
            'm_ipc.getSocket1Reply("dispatch workspace " + std::to_string(id()));' \
            'm_ipc.getSocket1Reply("dispatch hl.dsp.focus({ workspace = \"" + std::to_string(id()) + "\" })");'

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
