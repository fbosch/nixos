{ pkgs, inputs, options, lib, ... }:
let
  theme =
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.modern-grub2;
in
{
  system.stateVersion = "25.05";
  hardware.bluetooth.enable = false;

  boot = {
    # Hide boot messages for clean splash screen experience
    consoleLogLevel = 3; # Show only errors and critical messages
    kernelParams = [
      "quiet" # Suppress most kernel messages
      "splash" # Enable splash screen
      "vt.global_cursor_default=0" # Hide cursor
      "udev.log_level=3" # Reduce udev verbosity
      "rd.systemd.show_status=auto" # Only show status on errors
      "rd.udev.log_level=3" # Reduce initrd udev verbosity

      # VirtualBox graphics optimizations
      "vboxguest.disable_cursor_plane=1" # Disable hardware cursor in VirtualBox
    ];

    loader.grub = {
      enable = true;
      device = "/dev/sda";
      useOSProber = true;
      configurationLimit = 42;
      theme = "${theme}/tela";
      splashImage = "${theme}/tela/background.jpg";
      gfxmodeBios = "1920x1080,auto";
    };

    plymouth = {
      enable = true;
      theme = "monoarch-refined";
      themePackages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.monoarch-plymouth ];
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
  };

  networking = {
    hostName = "rvn-vm";
    networkmanager.enable = true;
    timeServers = options.networking.timeServers.default ++ [ "time.nist.gov" ];
  };

  zramSwap.enable = true;
  security.polkit.enable = true;

  services = {
    upower.enable = true;
    dbus.enable = true;
    timesyncd.enable = true;
    ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };
    spice-vdagentd.enable = true;

    # Disable system76-scheduler (conflicts with ananicy-cpp and uses eBPF unnecessarily in VM)
    system76-scheduler.enable = lib.mkForce false;
  };

  environment.systemPackages = with pkgs; [ foot xdg-utils ];

}
