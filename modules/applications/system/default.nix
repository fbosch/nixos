{ config, ... }:
{
  flake.modules = {
    nixos.applications = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        hardinfo2
        mission-center
      ];

      # Mission Center uses nethogs for per-process network monitoring.
      # Without cap_dac_read_search and cap_sys_ptrace, nethogs can attribute
      # traffic only to the invoking user's processes; other traffic is unknown.
      security.wrappers.nethogs = {
        source = "${pkgs.nethogs}/bin/nethogs";
        owner = "root";
        group = "nethogs";
        permissions = "u+rx,g+x";
        capabilities = "cap_net_admin,cap_net_raw+pe";
      };

      # users.nix forces extraGroups, so grant membership from the group side.
      users.groups.nethogs.members = [ config.flake.meta.user.username ];

      # Allow Mission Center to read Intel RAPL energy counters for CPU power usage.
      services.udev.extraRules = ''
        SUBSYSTEM=="powercap", KERNEL=="intel-rapl*", RUN+="${pkgs.coreutils}/bin/chmod a+r /sys/%p/energy_uj"
      '';
    };
  };
}
