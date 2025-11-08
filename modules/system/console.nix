{
  flake.modules.nixos.system = {
    # Zenwritten dark theme - grayscale colors for virtual console (TTY)
    # 16-color palette: colors 0-15 (hex without # prefix)
    console.colors = [
      # Standard colors (0-7) - grayscale
      "1a1a1a" # 0: black (very dark gray - background)
      "4a4a4a" # 1: dark gray (red position)
      "5a5a5a" # 2: medium-dark gray (green position)
      "6a6a6a" # 3: medium gray (yellow position)
      "7a7a7a" # 4: medium-light gray (blue position)
      "8a8a8a" # 5: light gray (magenta position)
      "9a9a9a" # 6: lighter gray (cyan position)
      "e5e5e5" # 7: white (very light gray - foreground)
      # Bright colors (8-15) - brighter grayscale
      "2a2a2a" # 8: bright black (slightly lighter dark gray)
      "5a5a5a" # 9: bright red (medium gray)
      "6a6a6a" # 10: bright green (medium gray)
      "7a7a7a" # 11: bright yellow (medium-light gray)
      "8a8a8a" # 12: bright blue (light gray)
      "9a9a9a" # 13: bright magenta (lighter gray)
      "aaaaaa" # 14: bright cyan (light gray)
      "ffffff" # 15: bright white (pure white)
    ];
  };
}
