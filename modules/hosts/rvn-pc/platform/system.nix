{ config, ... }:
{
  flake.modules.nixos."hosts/rvn-pc/platform" =
    { pkgs, ... }:
    let
      inherit (config.flake.lib) lazyDesktopApp;

      lazyKeymapp = lazyDesktopApp pkgs {
        pkg = pkgs.keymapp;
        desktopItem = {
          name = "keymapp";
          exec = "keymapp";
          desktopName = "Keymapp";
          icon = ../../../../assets/icons/keymapp.png;
          terminal = false;
          categories = [
            "Settings"
            "HardwareSettings"
          ];
        };
      };
    in
    {
      environment.etc."xdg/weston/weston.ini".text = ''
        [core]
        shell=kiosk
        cursor-theme=WinSur-white-cursors
        cursor-size=28

        [output]
        name=DP-2
        mode=3440x1440@164.9

        [output]
        name=HDMI-A-2
        mode=off
      '';

      services.displayManager.sddm.settings = {
        Theme = {
          CursorTheme = "WinSur-white-cursors";
          CursorSize = 28;
        };
        Wayland.CompositorCommand = "${pkgs.weston}/bin/weston --shell=kiosk -c /etc/xdg/weston/weston.ini";
      };

      system.stateVersion = "25.11";

      nixpkgs.config.allowUnfree = true;

      hardware.bluetooth.enable = false;

      services = {
        upower.enable = true;
        dbus.enable = true;
        power-profiles-daemon.enable = true;
        timesyncd.enable = true;
        fstrim.enable = true;
        ananicy = {
          enable = true;
          package = pkgs.ananicy-cpp;
          rulesProvider = pkgs.ananicy-rules-cachyos;
        };
      };

      zramSwap.enable = true;

      boot.kernel.sysctl = {
        "vm.swappiness" = 10;
        "vm.vfs_cache_pressure" = 50;
      };

      security.polkit.enable = true;

      environment.systemPackages = with pkgs; [
        wget
        vim
        neovim
        lazyKeymapp
      ];
    };
}
