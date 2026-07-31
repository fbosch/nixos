{
  flake.modules.darwin."macos-defaults" = {
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
        NSAutomaticWindowAnimationsEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSScrollAnimationEnabled = false;
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

        "com.knollsoft.Rectangle" = {
          allowAnyShortcut = 1;
          alternateDefaultShortcuts = 1;
          launchOnLogin = 1;
          windowSnapping = 1;
        };

        "com.apple.finder" = {
          DisableAllAnimations = true;
        };

        "com.apple.dock" = {
          springboard-hide-duration = 0.0;
          springboard-page-duration = 0.0;
          springboard-show-duration = 0.0;
        };

        "com.lwouis.alt-tab-macos" = {
          cursorFollowFocus = 1;
          cursorFollowFocusEnabled = true;
          hideAppBadges = false;
          hideColoredCircles = true;
          hideSpaceNumberLabels = true;
          hideStatusIcons = true;
          hideWindowlessApps = true;
          previewFocusedWindow = true;
          showTabsAsWindows = false;
          vimKeysEnabled = false;
        };
      };
    };
  };
}
