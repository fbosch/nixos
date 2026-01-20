_:
{
  flake.modules.nixos.system = {
    # Enable System76 Scheduler for improved desktop responsiveness
    # Optimizes CPU scheduling and assigns process priorities automatically
    # Particularly beneficial for gaming performance and UI smoothness
    services.system76-scheduler = {
      enable = true;

      # Enable foreground process boosting
      # Works with Hyprland via DBus to prioritize active window processes
      settings.processScheduler.foregroundBoost = {
        enable = true;

        # Configure background process priorities
        background = {
          class = "batch"; # Use batch scheduling for background processes
          ioClass = "best-effort";
          ioPrio = 7; # Lowest I/O priority (0-7, where 7 is lowest)
        };
      };
    };

    # Custom process priority assignments can be added in:
    # /etc/system76-scheduler/process-scheduler/*.kdl
  };
}
