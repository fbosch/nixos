{
  flake.modules.nixos."hosts/rvn-pc/boot" =
    { lib
    , options
    , pkgs
    , ...
    }:
    {
      boot = {
        # Hide boot messages for clean splash screen experience
        consoleLogLevel = 3; # Show only errors and critical messages
        kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
        kernelModules = [ "ntsync" ];
        initrd.kernelModules = lib.mkForce [
          "dm_mod"
          "i915"
          "nvidia"
          "nvidia_modeset"
          "nvidia_drm"
          "rtc_cmos"
        ];
        kernelParams = [
          "quiet" # Suppress most kernel messages
          "splash" # Enable splash screen
          "vt.global_cursor_default=1" # Keep cursor visible
          "udev.log_level=3" # Reduce udev verbosity
          "rd.systemd.show_status=false" # Keep splash instead of initrd status output
          "systemd.show_status=false" # Keep splash instead of userspace status output
          "rd.udev.log_level=3" # Reduce initrd udev verbosity
          "fbcon=nodefer"
          # HDR support for NVIDIA
          "nvidia_drm.modeset=1" # Enable modesetting (required for HDR)
          "nvidia_drm.fbdev=1"
          "nvidia.NVreg_EnableGpuFirmware=0" # Improve compatibility
          # NVIDIA suspend support
          "nvidia.NVreg_PreserveVideoMemoryAllocations=1" # Preserve video memory allocations for suspend
          "nvidia.NVreg_UsePageAttributeTable=1" # Improve GPU memory performance
          "nvidia.NVreg_EnableStreamMemOPs=1" # Enable stream memory operations
          # Use deep suspend mode for better NVIDIA compatibility
          "mem_sleep_default=deep" # More reliable suspend with NVIDIA GPUs
          # Keep transparent huge pages available without forcing always-on compaction
          "transparent_hugepage=madvise"
        ];

        # Optimize tmpfs usage for 32GB RAM system
        initrd.verbose = false;

        tmp = {
          useTmpfs = true;
          tmpfsSize = "16G"; # ~50% of RAM for temporary files
        };

        loader = {
          grub = {
            enable = true;
            device = "nodev";
            efiSupport = true;
            useOSProber = true;
            configurationLimit = 42;
            extraConfig = ''
              # Use maximum supported resolution (1080p)
              set gfxmode=1920x1080
              insmod all_video
              insmod gfxterm
              terminal_output gfxterm
            '';
          };

          efi.canTouchEfiVariables = true;
        }
        // lib.optionalAttrs (options.boot.loader ? "grub2-theme") {
          grub2-theme = {
            enable = true;
            theme = "whitesur";
            icon = "white";
            screen = "1080p";
            footer = true;
            splashImage = ./../../../assets/grub-backgrounds/black.jpg;
          };
        };

        plymouth = {
          enable = true;
          theme = "monoarch-refined";
          themePackages = [ pkgs.local.monoarch-plymouth ];
        };
      };

      boot.initrd.systemd.services.plymouth-start = {
        after = [ "systemd-modules-load.service" ];
        wants = [ "systemd-modules-load.service" ];
      };
    };
}
