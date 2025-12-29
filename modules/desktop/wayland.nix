_: {
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        xorg.xrdb
        xorg.xhost
        xorg.xrandr
        xorg.xprop
        xorg.xwininfo
      ];
    };

  flake.modules.homeManager.desktop =
    { pkgs, inputs, ... }:
    {
      home.packages = with pkgs; [
        # waycorner
        # rofi
        xwayland
        xwayland-satellite
        inputs.ags.packages.${pkgs.stdenv.hostPlatform.system}.default
        wev
        nwg-look
        nwg-displays
        wlr-randr
        wl-clipboard
        wl-clipboard-x11
        cliphist
        wl-clip-persist
        waybar
        swaynotificationcenter
        swayimg
        libnotify
        swayosd
        gsettings-desktop-schemas
      ];

      systemd.user.services.cliphist = {
        Unit = {
          Description = "Clipboard history service for Wayland";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
          Restart = "on-failure";
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      systemd.user.services.wl-clip-persist = {
        Unit = {
          Description = "Persist Wayland clipboard after programs exit";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = "${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard both";
          Restart = "on-failure";
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
