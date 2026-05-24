_: {
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
        # sgdboop - disabled due to build error in nixpkgs (function signature mismatch)
        nvitop
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
  };
}
