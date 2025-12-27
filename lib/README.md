# Library Functions

Reusable Nix utility functions for the nixos configuration.

## icon-overrides.nix

Provides `applyIconOverrides` function to customize icon themes by replacing specific icons.

### Usage

```nix
let
  iconOverrideLib = import ./lib/icon-overrides.nix { inherit pkgs; inherit (pkgs) lib; };
in
  iconOverrideLib.applyIconOverrides {
    basePackage = myIconTheme;
    themeName = "MyTheme";
    overrides = [
      # Override with icon from same context/size
      {
        name = "folder";
        useBuiltin = "folder-open";
        sizes = [ "16" "22" "24" ];
        context = "places";
      }
      
      # Override with icon from different path (auto-resized)
      {
        name = "folder-open-symbolic";
        useBuiltinFrom = "places/scalable/folder-open";
        sizes = [ "symbolic" ];
        context = "places";
      }
      
      # Override with custom icon from assets (auto-resized)
      {
        name = "discord";
        source = ../assets/icons/discord.svg;
        sizes = [ "scalable" "22" "32" ];
        context = "apps";
      }
    ];
  }
```

### Override Specification

Each override requires:
- `name`: Icon filename to replace (without .svg extension)
- `sizes`: List of size directories (e.g., "16", "22", "24", "scalable", "symbolic")
- `context`: Icon context directory (e.g., "apps", "places", "actions", "devices")

Plus **one** of:
- `useBuiltin`: Icon name from same context/size directory
- `useBuiltinFrom`: Path to icon relative to theme directory (will be auto-resized)
- `source`: Absolute path to custom SVG file (will be auto-resized)

### Features

- Automatic SVG resizing using `rsvg-convert`
- Supports all standard icon sizes (16, 22, 24, 32, 48, 64, scalable, symbolic)
- Automatically updates icon cache after applying overrides
- Works with any icon theme that follows freedesktop.org icon theme specification
