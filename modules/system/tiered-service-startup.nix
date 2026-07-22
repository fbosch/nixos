_: {
  flake.modules.nixos."system/tiered-service-startup" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.startupPolicy;
      appTarget = name: "startup-policy-app-${name}.target";
      apps = cfg.applications;
      appNames = builtins.attrNames apps;
      appUnits = lib.concatMap (app: map (unit: unit // { inherit app; }) apps.${app}.units) appNames;
      appNamesForTier = tier: lib.filter (name: apps.${name}.tier == tier) appNames;
      nativeUnits = lib.filter (unit: unit.provider == "nixos") appUnits;
      quadletUnits = lib.filter (unit: unit.provider == "quadlet") appUnits;
      backgroundOrder = appNamesForTier "background";
      systemctl = "${pkgs.systemd}/bin/systemctl";
      backgroundDispatcher = pkgs.writeShellScript "startup-policy-background-dispatch" ''
        set -u

        for target in ${lib.escapeShellArgs (map appTarget backgroundOrder)}; do
          if ${systemctl} start "$target"; then
            echo "startup-policy: started $target"
          else
            echo "startup-policy: failed to start $target" >&2
          fi
        done
      '';
    in
    {
      options.services.startupPolicy = {
        applications = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                tier = lib.mkOption {
                  type = lib.types.enum [
                    "essential"
                    "standard"
                    "background"
                  ];
                  description = "Startup tier for this application group.";
                };

                units = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.submodule {
                      options = {
                        name = lib.mkOption {
                          type = lib.types.str;
                          description = "Systemd service unit managed by this application group.";
                        };

                        provider = lib.mkOption {
                          type = lib.types.enum [
                            "nixos"
                            "quadlet"
                          ];
                          description = "Whether NixOS or Quadlet owns the unit file.";
                        };
                      };
                    }
                  );
                  default = [ ];
                  description = "Units that form one application startup transaction.";
                };
              };
            }
          );
          default = { };
          description = "Explicit startup tiers for application service groups.";
        };

        quadletUnitSettings = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                target = lib.mkOption {
                  type = lib.types.str;
                  description = "Install target for the Quadlet-generated service unit.";
                };

                slice = lib.mkOption {
                  type = lib.types.str;
                  description = "Resource slice for the Quadlet-generated service unit.";
                };
              };
            }
          );
          readOnly = true;
          description = "Resolved startup settings for Quadlet-generated service units.";
        };
      };

      config = lib.mkIf (apps != { }) {
        assertions = [
          {
            assertion = lib.all (name: apps.${name}.units != [ ]) appNames;
            message = "startupPolicy application groups must declare at least one service unit.";
          }
          {
            assertion = lib.all (unit: lib.hasSuffix ".service" unit.name) appUnits;
            message = "startupPolicy application units must be service units.";
          }
          {
            assertion = lib.length (lib.unique (map (unit: unit.name) appUnits)) == lib.length appUnits;
            message = "startupPolicy assigns each service unit to exactly one application.";
          }
        ];

        services.startupPolicy = {
          quadletUnitSettings = lib.listToAttrs (
            map
              (
                unit:
                lib.nameValuePair unit.name {
                  target = appTarget unit.app;
                  slice =
                    if apps.${unit.app}.tier == "background" then "startup-policy-background.slice" else "system.slice";
                }
              )
              quadletUnits
          );
        };

        systemd = {
          targets =
            (lib.listToAttrs (
              map
                (
                  name:
                  lib.nameValuePair "startup-policy-app-${name}" {
                    description = "Startup policy application: ${name}";
                    wants = map (unit: unit.name) apps.${name}.units;
                  }
                )
                appNames
            ))
            // {
              startup-policy-essential = {
                description = "Essential application startup policy";
                wants = map appTarget (appNamesForTier "essential");
                before = [ "multi-user.target" ];
                wantedBy = [ "multi-user.target" ];
              };

              startup-policy-standard = {
                description = "Standard application startup policy";
                wants = map appTarget (appNamesForTier "standard");
              };
            };

          services =
            (lib.listToAttrs (
              map
                (
                  unit:
                  lib.nameValuePair (lib.removeSuffix ".service" unit.name) {
                    wantedBy = lib.mkForce [ (appTarget unit.app) ];
                    serviceConfig = lib.mkIf (apps.${unit.app}.tier == "background") {
                      Slice = lib.mkDefault "startup-policy-background.slice";
                    };
                  }
                )
                nativeUnits
            ))
            // {
              startup-policy-standard-dispatch = {
                description = "Start standard and background application tiers";
                after = [ "multi-user.target" ];
                serviceConfig.Type = "oneshot";
                script = ''
                  ${systemctl} start startup-policy-standard.target
                  ${systemctl} start --no-block startup-policy-background.service
                '';
              };

              startup-policy-background = {
                description = "Start background application tier";
                after = [ "startup-policy-standard.target" ];
                serviceConfig.Type = "oneshot";
                script = "exec ${backgroundDispatcher}";
              };
            };

          timers.startup-policy-standard-dispatch = {
            wantedBy = [ "timers.target" ];
            timerConfig.OnBootSec = "0";
          };

          slices.startup-policy-background = {
            description = "Low-priority background application services";
            sliceConfig = {
              CPUWeight = 25;
              IOWeight = 25;
            };
          };
        };
      };
    };
}
