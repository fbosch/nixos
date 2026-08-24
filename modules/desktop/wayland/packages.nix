{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      xrdb
      xhost
      xrandr
      xprop
      xwininfo
      xwayland
      xwayland-satellite
      setxkbmap
      wev
      nwg-look
      nwg-displays
      wlr-randr
      wl-clipboard
      xclip
      xsel
      autocutsel
      cliphist
      wl-clip-persist
      wtype
      xdotool
      (swaynotificationcenter.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace data/ui/notification.blp \
            --replace-fail \
            $'                Overlay {\n                  halign: center;\n                  valign: center;' \
            $'                Overlay {\n                  halign: center;\n                  valign: start;\n\n                  styles [\n                    "notification-image-overlay",\n                  ]'
        '';
      }))
      libnotify
      swayosd
      gsettings-desktop-schemas
      awww
    ];
  };
}
