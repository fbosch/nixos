{
  flake.modules.nixos."hosts/rvn-pc/platform" =
    { pkgs, ... }:
    {
      system.stateVersion = "25.11";

      nixpkgs.config.allowUnfree = true;

      hardware.bluetooth.enable = false;

      services = {
        upower.enable = true;
        dbus.enable = true;
        timesyncd.enable = true;
        fstrim.enable = true;
        ananicy = {
          enable = true;
          package = pkgs.ananicy-cpp;
          rulesProvider = pkgs.ananicy-rules-cachyos;
        };
      };

      zramSwap.enable = true;

      boot.kernel.sysctl = {
        "vm.swappiness" = 10;
        "vm.vfs_cache_pressure" = 50;
      };

      security.polkit.enable = true;

      environment.systemPackages = with pkgs; [
        wget
        vim
        neovim
      ];
    };
}
