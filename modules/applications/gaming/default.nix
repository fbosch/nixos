_: {
  # NixOS module: Generic gaming system configuration
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        mangohud
        wowup-cf
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
            NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
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
