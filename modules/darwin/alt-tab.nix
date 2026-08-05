{
  flake.modules.darwin."alt-tab" = {
    homebrew.casks = [ "alt-tab" ];

    system.defaults.CustomUserPreferences."com.lwouis.alt-tab-macos" = {
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
}
