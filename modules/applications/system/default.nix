{
  flake.modules = {
    nixos.applications = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        hardinfo2
        mission-center
      ];

      # Mission Center uses nethogs for per-process network monitoring.
      security.wrappers.nethogs = {
        source = "${pkgs.nethogs}/bin/nethogs";
        owner = "root";
        group = "root";
        capabilities = "cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe";
      };

      # Allow Mission Center to read Intel RAPL energy counters for CPU power usage.
      services.udev.extraRules = ''
        SUBSYSTEM=="powercap", KERNEL=="intel-rapl*", RUN+="${pkgs.coreutils}/bin/chmod a+r /sys/%p/energy_uj"
      '';
    };
  };
}
