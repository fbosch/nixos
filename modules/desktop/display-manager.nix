_: {
  flake.modules.nixos.desktop =
    {
      pkgs,
      lib,
      config,
      meta,
      hostConfig ? { },
      ...
    }:
    let
      # Get display manager mode from hostConfig or use default
      displayManagerMode = hostConfig.displayManagerMode or meta.displayManager.defaultMode;
      
      # TUIGreet configuration
      tuigreetTheme = builtins.readFile ../../configs/greetd/theme.txt;
      nixosVersion = "${config.system.nixos.release} ${config.system.nixos.codeName}";
      issueText = builtins.readFile ../../configs/greetd/issue.txt;
      
      # Session script (shared between tuigreet and autologin)
      sessionScript = builtins.readFile ../../configs/greetd/session-hyprland.sh;
      
      username = meta.user.username;
    in
    {
      # Export environment variable for Hyprland to know if it should launch hyprlock
      # Available in Hyprland as $HYPRLOCK_AT_LAUNCH
      environment.sessionVariables = {
        HYPRLOCK_AT_LAUNCH = if displayManagerMode == "hyprlock-autologin" then "true" else "false";
      };

      environment.etc = {
        "issue" = lib.mkIf (displayManagerMode == "tuigreet") {
          text = ''
            ${issueText}
            ${nixosVersion}
          '';
        };

        "greetd/session-hyprland" = {
          text = sessionScript;
          mode = "0755";
        };
      };

      services.greetd = {
        enable = true;
        settings = {
          default_session = 
            if displayManagerMode == "hyprlock-autologin" then {
              # Autologin: start Hyprland session directly
              command = "/etc/greetd/session-hyprland";
              user = username;
            } else {
              # TUIGreet: show login screen
              command = ''
                ${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --asterisks --issue --greet-align center --theme ${lib.escapeShellArg (lib.removeSuffix "\n" tuigreetTheme)} --sessions "" --cmd /etc/greetd/session-hyprland
              '';
              user = "greeter";
            };
        };
      };

      systemd.services.greetd = {
        wantedBy = [ "graphical.target" ];
      };

      security.pam.services.greetd.enableGnomeKeyring = true;
    };
}
