{ config, ... }:
{
  # NixOS module: Generic gaming system configuration
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    let
      inherit (config.flake.lib) lazyApp;

      lazyProtontricks = lazyApp pkgs {
        pkg = pkgs.protontricks;
        exe = "protontricks";
        desktopItems = [
          (pkgs.makeDesktopItem {
            name = "protontricks";
            exec = "protontricks --no-term --gui";
            desktopName = "Protontricks";
            comment = "A simple wrapper that does winetricks things for Proton enabled games";
            terminal = false;
            categories = [ "Utility" ];
            icon = "wine";
            keywords = [
              "Steam"
              "Proton"
              "Wine"
              "Winetricks"
            ];
          })
        ];
      };

      lazyProtontricksLaunch = lazyApp pkgs {
        pkg = pkgs.protontricks;
        exe = "protontricks-launch";
        desktopItems = [
          (pkgs.makeDesktopItem {
            name = "protontricks-launch";
            exec = "protontricks-launch --no-term %f";
            desktopName = "Protontricks Launcher";
            terminal = false;
            noDisplay = true;
            categories = [ "Utility" ];
            icon = "wine";
            mimeTypes = [
              "application/x-ms-dos-executable"
              "application/x-msi"
              "application/x-ms-shortcut"
            ];
          })
        ];
      };

      lazyProtonupQt = lazyApp pkgs {
        pkg = pkgs.protonup-qt;
        desktopItems = [
          (pkgs.makeDesktopItem {
            name = "protonup-qt";
            exec = "protonup-qt";
            desktopName = "ProtonUp-Qt";
            comment = "Install Wine and Proton-based Compatibility Tools";
            terminal = false;
            icon = "protonup-qt";
            categories = [
              "Game"
              "Utility"
            ];
          })
        ];
      };

      wowup-cf-wayland = pkgs.symlinkJoin {
        name = "wowup-cf-wayland";
        paths = [ pkgs.wowup-cf ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/wowup-cf \
            --set ELECTRON_OZONE_PLATFORM_HINT wayland \
            --set NIXOS_OZONE_WL 1 \
            --add-flags --use-gl=angle \
            --add-flags --use-angle=opengl
        '';
      };
    in
    {
      environment.systemPackages = with pkgs; [
        mangohud
        wowup-cf-wayland
        lazyProtontricks
        lazyProtontricksLaunch
        wineWow64Packages.stable
        vulkan-tools
        lazyProtonupQt
        wl-freeze
        # sgdboop - disabled due to build error in nixpkgs (function signature mismatch)
        (lazyApp pkgs nvitop)
        prismlauncher # Minecraft launcher
      ];

      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;

      programs = {
        gamescope = {
          enable = true;
          package = pkgs.gamescope.overrideAttrs (_: {
            NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ]; # fixes weird stutter in wow when turning camera
          });
        };

        # Required for gaming performance
        gamemode.enable = true;
      };
    };

  # Home Manager module: Generic gaming user applications
  flake.modules.homeManager.applications = {
    # Flatpak gaming applications
    services.flatpak.packages = [
      "org.freedesktop.Platform.VulkanLayer.vkBasalt//25.08" # Vulkan post-processing
      "org.freedesktop.Platform.VulkanLayer.MangoHud//25.08" # MangoHud overlay
      "io.mgba.mGBA" # GBA emulator
    ];

    xdg.desktopEntries.wowup-cf = {
      name = "WowUp-CF";
      exec = "env ELECTRON_OZONE_PLATFORM_HINT=wayland NIXOS_OZONE_WL=1 wowup-cf --no-sandbox --use-gl=angle --use-angle=opengl %U";
      icon = "wowup-cf";
      type = "Application";
      categories = [ "Game" ];
      terminal = false;
      settings = {
        StartupWMClass = "WowUp-CF";
        X-AppImage-Version = "2.22.0";
      };
    };
  };
}
