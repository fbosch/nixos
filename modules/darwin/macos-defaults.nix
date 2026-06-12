{
  flake.modules.darwin."macos-defaults" = {
    system.defaults = {
      dock = {
        autohide = true;
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
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSWindowShouldDragOnGesture = true;
        "com.apple.swipescrolldirection" = false;
      };

      CustomUserPreferences = {
        NSGlobalDomain.NSUserKeyEquivalents = {
          Hide = "@^~$h";
          "Hide Others" = "@^~$o";
        };

        "com.knollsoft.Rectangle" = {
          allowAnyShortcut = 1;
          alternateDefaultShortcuts = 1;
          launchOnLogin = 1;
          windowSnapping = 1;
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
