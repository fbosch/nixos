{
  flake.modules.darwin.hazeover = {
    homebrew.casks = [ "hazeover" ];

    system.defaults.CustomUserPreferences."com.pointum.hazeover" = {
      Animation = 0;
      AnimationCurve = 3;
      AppRules = { };
      AskSecondaryDisplay = 0;
      Color = 232323;
      Enabled = 1;
      IndependentScreens = 0;
      Intensity = "30.3081931043206";
      SettingsTab = 0;
      UsingAX = 1;
    };
  };
}
