let
  systemDefaults = {
    system.defaults = {
      dock = {
        autohide = true;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.0;
        expose-animation-duration = 0.1;
        orientation = "bottom";
        show-recents = false;
        tilesize = 48;
        launchanim = false;
      };

      finder = {
        AppleShowAllExtensions = true;
        FXPreferredViewStyle = "Nlsv";
        ShowPathbar = true;
      };

      menuExtraClock = {
        Show24Hour = true;
        ShowDate = 0;
        ShowDayOfWeek = true;
      };

      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleShowAllExtensions = true;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticWindowAnimationsEnabled = true;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSScrollAnimationEnabled = true;
        NSWindowShouldDragOnGesture = true;
        "com.apple.swipescrolldirection" = false;
      };

      CustomUserPreferences = {
        NSGlobalDomain.NSUserKeyEquivalents = {
          Hide = "@^~$h";
          "Hide Others" = "@^~$o";
        };

        NSGlobalDomain = {
          NSBrowserColumnAnimationSpeedMultiplier = 0.0;
          NSDocumentRevisionsWindowTransformAnimation = false;
          NSScrollViewRubberbanding = false;
          NSToolbarFullScreenAnimationDuration = 0.0;
          NSWindowResizeTime = 0.001;
          QLPanelAnimationDuration = 0.0;
        };

        "com.apple.finder" = {
          DisableAllAnimations = true;
        };

        "com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
          "28".enabled = false; # Command-Shift-3: save screen
          "29".enabled = false; # Control-Command-Shift-3: copy screen
          "30".enabled = false; # Command-Shift-4: save selection
          "31".enabled = false; # Control-Command-Shift-4: copy selection
          "184".enabled = false; # Command-Shift-5: screenshot toolbar

          # Release Command-Space from Spotlight for Vicinae's global shortcut.
          "64".enabled = false;
        };

        "com.apple.dock" = {
          springboard-hide-duration = 0.0;
          springboard-page-duration = 0.0;
          springboard-show-duration = 0.0;
          # Disable the bottom-right Quick Note hot corner and its modifier.
          wvous-br-corner = 0;
          wvous-br-modifier = 0;
        };

      };
    };
  };
  symbolicHotkeys = systemDefaults.system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys;
in
{
  flake.modules.darwin."system-defaults" = systemDefaults;

  perSystem.nix-unit.tests.darwinSystemDefaults = {
    testNativeScreenshotShortcutsAreDisabled = {
      expr = map (id: symbolicHotkeys.${id}.enabled or true) [ "28" "29" "30" "31" "184" ];
      expected = [ false false false false false ];
    };

    testOnlyIntendedSymbolicHotkeysAreManaged = {
      expr = builtins.attrNames symbolicHotkeys;
      expected = [ "184" "28" "29" "30" "31" "64" ];
    };
  };
}
