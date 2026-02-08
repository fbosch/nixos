{
  flake.modules.nixos.applications = _: { services.flatpak.enable = true; };
  flake.modules.homeManager.applications = _: {
    services.flatpak = {
      enable = true;
      uninstallUnmanaged = true;
      update = {
        onActivation = true;
        auto = {
          enable = true;
          onCalendar = "weekly";
        };
      };
      remotes = [
        {
          name = "flathub";
          location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
        }
      ];
      packages = [
        # Flatpak management tools
        "com.github.tchx84.Flatseal" # Flatpak permission manager
        "io.github.flattool.Warehouse" # Flatpak app manager
      ];

      # Global Flatpak overrides applied to all applications
      # App-specific overrides are defined in their respective domain modules
      overrides = {
        global = {
          Context.sockets = [
            "wayland"
            "!x11"
            "!fallback-x11"
          ];
          Context.filesystems = [
            "xdg-config/fontconfig:ro"
            "~/.local/share/fonts:ro"
            "/nix/store:ro"
          ];
        };
      };
    };
  };
}
