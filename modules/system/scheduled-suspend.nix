{ config, ... }:
{
  flake.modules.nixos."system/scheduled-suspend" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      options.powerManagement.scheduledSuspend = {
        enable = lib.mkEnableOption "scheduled suspend and wake";

        schedules = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                suspendTime = lib.mkOption {
                  type = lib.types.str;
                  example = "23:00";
                  description = "Time to suspend the system (24-hour format)";
                };

                wakeTime = lib.mkOption {
                  type = lib.types.str;
                  example = "07:00";
                  description = "Time to wake the system (24-hour format)";
                };

                days = lib.mkOption {
                  type = lib.types.str;
                  default = "*-*-*";
                  example = "Mon,Tue,Wed,Thu,Fri";
                  description = "Days when this schedule applies (systemd calendar format)";
                };
              };
            }
          );
          default = { };
          example = {
            weekday = {
              suspendTime = "23:00";
              wakeTime = "06:30";
              days = "Mon,Tue,Wed,Thu,Fri";
            };
            weekend = {
              suspendTime = "01:00";
              wakeTime = "09:00";
              days = "Sat,Sun";
            };
          };
          description = "Multiple suspend/wake schedules";
        };
      };

      config = lib.mkIf config.powerManagement.scheduledSuspend.enable {
        systemd =
          let
            mkSuspendTimer = name: schedule: {
              "scheduled-suspend-${name}" = {
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnCalendar = "${schedule.days} ${schedule.suspendTime}";
                  Persistent = true;
                };
              };
            };

            mkSuspendService = name: schedule: {
              "scheduled-suspend-${name}" = {
                description = "Scheduled system suspend (${name})";
                serviceConfig = {
                  Type = "oneshot";
                };

                script = ''
                  # Calculate tomorrow's wake time timestamp
                  WAKE_TIME="${schedule.wakeTime}"
                  TOMORROW=$(date -d "tomorrow $WAKE_TIME" +%s)

                  # Set RTC wake alarm and suspend
                  # -m mem: suspend to RAM
                  # -t: wake time as Unix timestamp
                  ${pkgs.util-linux}/bin/rtcwake -m mem -t $TOMORROW
                '';
              };
            };

            schedules = config.powerManagement.scheduledSuspend.schedules;
          in
          {
            timers = lib.mkMerge (lib.mapAttrsToList mkSuspendTimer schedules);
            services = lib.mkMerge (lib.mapAttrsToList mkSuspendService schedules);
          };
      };
    };
}
