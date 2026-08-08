{ inputs
, lazyDesktopApp
,
}:
pkgs:
let
  lazyNwgLook = lazyDesktopApp pkgs {
    pkg = pkgs.nwg-look;
    desktopItem = {
      name = "nwg-look";
      exec = "nwg-look";
      desktopName = "GTK Settings";
      genericName = "Adjust Look and Feel";
      comment = "Customizes GTK3 look and feel settings";
      icon = ./nwg-look.svg;
      terminal = false;
      notShowIn = [
        "GNOME"
        "KDE"
        "XFCE"
        "MATE"
      ];
      startupNotify = true;
      categories = [
        "GTK"
        "Settings"
        "DesktopSettings"
      ];
      keywords = [
        "windows"
        "preferences"
        "settings"
        "theme"
        "style"
        "appearance"
        "look"
      ];
    };
  };

  lazyNwgDisplays = lazyDesktopApp pkgs {
    pkg = pkgs.nwg-displays;
    desktopItem = {
      name = "nwg-displays";
      exec = "nwg-displays";
      desktopName = "Displays Settings";
      genericName = "Output configuration utility";
      comment = "nwg-shell tool to configure outputs";
      icon = ./nwg-displays.svg;
      terminal = false;
      categories = [
        "Settings"
        "DesktopSettings"
      ];
    };
  };

  waybar = pkgs.waybar.overrideAttrs (old: {
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
  });
in
with pkgs;
[
  xwayland
  xwayland-satellite
  setxkbmap
  wev
  lazyNwgLook
  lazyNwgDisplays
  wlr-randr
  wl-clipboard
  xclip
  xsel
  autocutsel
  cliphist
  wl-clip-persist
  wtype
  xdotool
  waybar
  swaynotificationcenter
  libnotify
  swayosd
  gsettings-desktop-schemas
  awww
]
