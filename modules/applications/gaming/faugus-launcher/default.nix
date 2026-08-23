{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.faugus-launcher ];
    };

  flake.modules.homeManager.applications =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      faugusPrefixRequirements = [
        {
          selection = "GE-Proton Latest (default)";
          runner = "Proton-GE Latest";
          verbs = [ "vcrun2022" ];
        }
      ];
      faugusPrefixRequirementsFile = pkgs.writeText "faugus-prefix-requirements.tsv" (
        lib.concatMapStringsSep "\n"
          (
            requirement:
            "${requirement.selection}\t${requirement.runner}\t${lib.concatStringsSep " " (lib.sort builtins.lessThan (lib.unique requirement.verbs))}"
          )
          faugusPrefixRequirements
        + "\n"
      );
      faugusPrefixSetup = pkgs.writeShellApplication {
        name = "faugus-prefix-setup";
        runtimeInputs = [
          pkgs.cacert
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.jq
          pkgs.umu-launcher
          pkgs.util-linux
          pkgs.winetricks
        ];
        text = ''
          export CURL_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          export FAUGUS_PREFIX_REQUIREMENTS_FILE=${faugusPrefixRequirementsFile}
          export SSL_CERT_FILE=$CURL_CA_BUNDLE
          ${builtins.readFile ./scripts/prefix-setup.sh}
        '';
      };
      faugusLaunchArguments = [
        # Battle.net / World of Warcraft
        "GAMEID=umu-worldofwarcraft mullvad-exclude"
        "GAMEID=umu-infinitefusion mullvad-exclude"
        "GAMEID=umu-infinitefusionkanto"
        "GAMEID=umu-pokemonnova"
        "GAMEID=umu-elderscrollsonline mullvad-exclude"
      ];
      faugusLaunchPresets = pkgs.writeText "faugus-launch-presets.json" (
        builtins.toJSON faugusLaunchArguments
      );
      launcherSettings = pkgs.writeText "faugus-launcher-settings.json" (
        builtins.toJSON {
          default-prefix = "${config.home.homeDirectory}/Faugus";
          mangohud = "False";
          gamemode = "True";
          no-sleep-enabled = "False";
          default-runner = "";
          lossless-location = "${config.home.homeDirectory}/.steam/steam/steamapps/common/Lossless Scaling/Lossless.dll";
          discrete-gpu = "False";
          splash-window-enabled = "True";
          system-tray = "True";
          autostart-enabled = "False";
          mono-icon = "True";
          interface-mode = "List";
          labels-enabled = "False";
          logging-enabled = "False";
          wayland-driver = "True";
          wow64-enabled = "False";
          language = "en_US";
          show-hidden = "False";
          automatic-updates = "True";
          gamepad-navigation = "False";
          minimized-startup-enabled = "False";
          categories-and-sort-enabled = "False";
        }
      );
      globalEnvironment = pkgs.writeText "faugus-launcher-environment.json" (
        builtins.toJSON [
          "TZ=:/etc/localtime"
          "TZDIR=/usr/share/zoneinfo"
          "PROTON_NO_WM_DECORATION=1"
          "PROTON_USE_NTSYNC=1"
          "PROTON_ENABLE_NVAPI=1"
          "PROTON_DXVK_LOWLATENCY=1"
          "DXVK_HUD=0"
        ]
      );
    in
    {
      home = {
        packages = [ faugusPrefixSetup ];

        activation = {
          refreshFaugusLaunchPresets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            target="${config.xdg.dataHome}/faugus-launcher/presets.json"
            ${pkgs.coreutils}/bin/install -Dm644 ${faugusLaunchPresets} "$target"
          '';

          seedFaugusLauncherConfiguration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            config_file="${config.xdg.configHome}/faugus-launcher/config.json"
            legacy_config_file="${config.xdg.configHome}/faugus-launcher/config.ini"
            if [[ ! -e "$config_file" && ! -e "$legacy_config_file" ]]; then
              ${pkgs.coreutils}/bin/install -Dm644 ${launcherSettings} "$config_file"
            fi

            environment_file="${config.xdg.configHome}/faugus-launcher/envar.json"
            legacy_environment_file="${config.xdg.configHome}/faugus-launcher/envar.txt"
            if [[ ! -e "$environment_file" && ! -e "$legacy_environment_file" ]]; then
              ${pkgs.coreutils}/bin/install -Dm644 ${globalEnvironment} "$environment_file"
            fi
          '';
        };
      };

      xdg.desktopEntries.faugus-launcher = {
        name = "Faugus Launcher";
        exec = "gamemoderun env WINEFSYNC=1 WINEESYNC=1 DXVK_HUD=0 DXVK_STATE_CACHE=1 faugus-launcher %U";
        icon = "faugus-launcher";
        type = "Application";
        categories = [ "Game" ];
        startupNotify = false;
        terminal = false;
      };
    };
}
