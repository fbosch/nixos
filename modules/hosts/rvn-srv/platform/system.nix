{
  flake.modules.nixos."hosts/rvn-srv/platform" =
    { pkgs, ... }:
    {
      system.stateVersion = "25.11";

      nixpkgs.config.allowUnfree = true;

      environment.systemPackages = with pkgs; [
        wget
        neovim
        vim
      ];

      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
      };

      # Kernel tuning for server workload
      powerManagement.cpuFreqGovernor = "performance";

      security.apparmor = {
        enable = true;
        killUnconfinedConfinables = false;
      };

      boot.kernel.sysctl = {
        "vm.swappiness" = 10; # Only swap when critically low on RAM
        "vm.vfs_cache_pressure" = 50; # Keep filesystem cache longer
        "vm.dirty_ratio" = 15; # Start sync at 15% RAM dirty
        "vm.dirty_background_ratio" = 10; # Background writes at 10%

        # TCP optimizations for nginx/web serving (conservative values)
        "net.core.default_qdisc" = "fq"; # Fair Queuing - required for BBR pacing
        "net.ipv4.tcp_congestion_control" = "bbr"; # BBR: bandwidth-based congestion control
        "net.core.somaxconn" = 4096; # Increase max connection backlog
        "net.ipv4.tcp_max_syn_backlog" = 4096; # Match somaxconn to avoid SYN backlog bottleneck
        "net.ipv4.tcp_fastopen" = 3; # Enable TCP Fast Open (client + server)
        "net.ipv4.tcp_keepalive_time" = 600; # Keep connections alive longer
        "net.ipv4.tcp_keepalive_intvl" = 60;
        "net.ipv4.tcp_keepalive_probes" = 3;
        "net.core.netdev_max_backlog" = 5000; # Increase network device backlog

        # Socket buffer tuning for NAS (CIFS) throughput
        "net.core.rmem_max" = 16777216;
        "net.core.wmem_max" = 16777216;
        "net.ipv4.tcp_rmem" = "4096 87380 16777216";
        "net.ipv4.tcp_wmem" = "4096 65536 16777216";
      };

      # Scheduled suspend/wake for power savings
      powerManagement.scheduledSuspend = {
        schedules = {
          weekday = {
            suspendTime = "00:30";
            wakeTime = "06:00";
            days = "Mon,Tue,Wed,Thu";
          };
          friday = {
            suspendTime = "02:00";
            wakeTime = "06:00";
            days = "Fri";
          };
          weekend = {
            suspendTime = "02:00";
            wakeTime = "08:00";
            days = "Sat,Sun";
          };
        };
      };
    };
}
