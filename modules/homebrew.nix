{
  flake.modules.darwin.homebrew =
    { _ }:
    {
      # Base Homebrew configuration for macOS
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = true;
          cleanup = "zap"; # Uninstall packages not in config
          upgrade = true;
        };

        # GUI Applications (casks)
        casks = [
          "wezterm"
          "raycast"
          "numi"
          "font-noto-sans-runic"
          "rectangle"
          "bitwarden"
          "1password"
          "firefox"
          "floorp"
          "arc"
          "zen"
          "alt-tab"
          "replacicon"
          "cursor"
          "figma"
        ];

        # CLI tools that work better via Homebrew on macOS
        # (Most CLI tools should be in nixpkgs, but some may need Homebrew)
        brews = [
          # Add any brews here that don't work well in Nix
        ];
      };
    };
}
