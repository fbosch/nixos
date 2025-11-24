{ inputs, ... }:
{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      xwayland
      # xorg.xrdb
      # xorg.xhost
      # xorg.xrandr
      # xorg.xprop
      # xorg.xwininfo
    ];
  };

  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = with pkgs; [
      # waycorner
      inputs.ags.packages.${system}.default
      wev
      nwg-look
      nwg-displays
      wl-clipboard
      wl-clipboard-x11
      cliphist
      wl-clip-persist
      waybar
      swaynotificationcenter
      swayimg
      libnotify
      rofi
      swayosd
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
