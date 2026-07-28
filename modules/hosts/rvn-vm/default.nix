{ inputs
, config
, ...
}:
let
  hostMeta = {
    name = "rvn-vm";
    role = "vm";
    sshAlias = "vm";
    tailscale = null;
    local = null;
    sshPublicKey = null;
  };
in
{
  # rvn-vm: Dendritic host configuration for VirtualBox VM
  # Hardware: VirtualBox virtual machine
  # Role: Testing and development environment

  flake.meta.hosts = [ hostMeta ];

  flake.modules.nixos."hosts/rvn-vm" =
    { lib, pkgs, options, ... }:
    {
      imports = config.flake.lib.resolve [
        "hosts/rvn-vm/hardware"

        # Desktop preset (users, fonts, security, desktop, applications, development, shell, system, vpn)
        "presets/desktop"

        # system
        "secrets"
        "nas"
      ] ++ [
        inputs.grub2-themes.nixosModules.default
      ];

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

        loader = {
          grub = {
            enable = true;
            device = "/dev/sda";
            useOSProber = true;
            configurationLimit = 42;
            gfxmodeBios = "1920x1080,auto";
          };

          grub2-theme = {
            enable = true;
            theme = "whitesur";
            icon = "white";
            customResolution = "1920x1080";
            footer = true;
          };
        };

        plymouth = {
          enable = true;
          theme = "monoarch-refined";
          themePackages = [ pkgs.local.monoarch-plymouth ];
        };
      };

      nixpkgs.config.allowUnfree = true;

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
      };

      environment.systemPackages = with pkgs; [
        foot
        xdg-utils
      ];

      # Home Manager configuration for user
      home-manager.users.${config.flake.meta.user.username}.imports =
        config.flake.lib.resolveHm [
          # Desktop preset (includes users, dotfiles, fonts, security, desktop, applications, development, shell)
          "presets/desktop"

          # Shared modules with Home Manager components
          "secrets"
        ]
        ++ [
          # External Home Manager modules
          inputs.flatpaks.homeManagerModules.nix-flatpak
        ];

      # VirtualBox-specific environment variables for software rendering
      environment.sessionVariables = {
        GSK_RENDERER = lib.mkForce "cairo";
        WLR_RENDERER_ALLOW_SOFTWARE = "1";
        TERMINAL = "foot";
      };

      # Extend sudo timeout for VM convenience
      security.sudo.extraConfig = ''
        Defaults timestamp_timeout = 120
      '';
    };
}
