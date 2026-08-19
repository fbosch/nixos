{ inputs, ... }:
{
  # NixOS module: Generic gaming system configuration
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    let
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
        protontricks
        wineWow64Packages.stable
        vulkan-tools
        protonup-qt
        wl-freeze
        # sgdboop - disabled due to build error in nixpkgs (function signature mismatch)
        nvitop
        prismlauncher # Minecraft launcher
        inputs.hytale-launcher.packages.${pkgs.stdenv.hostPlatform.system}.hytale-launcher
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
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      hytaleLauncherIcon = pkgs.fetchurl {
        url = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/hytale.png";
        hash = "sha256-pBATM9a3+b2fRlo0kFGaoWe/YABcEI6X80TrrmNdnio=";
      };
    in
    {
      # Flatpak gaming applications
      services.flatpak.packages = [
        "org.freedesktop.Platform.VulkanLayer.vkBasalt//25.08" # Vulkan post-processing
        "org.freedesktop.Platform.VulkanLayer.MangoHud//25.08" # MangoHud overlay
        "io.mgba.mGBA" # GBA emulator
      ];

      xdg.dataFile."icons/hicolor/512x512/apps/hytale-launcher.png".source =
        hytaleLauncherIcon;

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
