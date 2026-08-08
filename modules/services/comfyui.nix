{ config, ... }:
let
  flakeConfig = config;
  dataDir = "/mnt/storage/ComfyUI";
  port = 8188;
in
{
  flake.modules.nixos."services/comfyui" =
    { lib
    , pkgs
    , ...
    }:
    let
      comfyuiPackage = pkgs.comfyui.override { withManager = true; };
      scriptRuntimeInputs = with pkgs; [
        coreutils
        curl
        libnotify
        systemd
        xdg-utils
      ];
      startComfyUI = pkgs.writeShellApplication {
        name = "comfyui-start";
        runtimeInputs = scriptRuntimeInputs;
        text = ''
          if systemctl is-active --quiet comfyui.service; then
            exec xdg-open http://127.0.0.1:${toString port}
          fi

          if ! systemctl start comfyui.service; then
            notify-send "ComfyUI" "Failed to start service"
            exit 1
          fi

          for _ in $(seq 1 90); do
            if curl --fail --silent --output /dev/null http://127.0.0.1:${toString port}; then
              exec xdg-open http://127.0.0.1:${toString port}
            fi

            if systemctl is-failed --quiet comfyui.service; then
              notify-send "ComfyUI" "Service crashed during startup"
              exit 1
            fi

            sleep 1
          done

          notify-send "ComfyUI" "Timed out waiting for http://127.0.0.1:${toString port}"
          exit 1
        '';
      };
    in
    {
      nix.settings = {
        extra-substituters = [ "https://cache.nixos-cuda.org" ];
        extra-trusted-public-keys = [
          "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        ];
      };

      # ComfyUI's PyTorch dependency inherits this setting when built.
      nixpkgs.config.cudaSupport = true;

      boot.kernelModules = [ "nvidia_uvm" ];

      services.comfyui = {
        enable = true;
        package = comfyuiPackage;
        inherit port;
        listen = [ "127.0.0.1" ];
        extraArgs = lib.mkForce [
          "--base-directory=${dataDir}"
          "--database-url=sqlite:///${dataDir}/user/comfyui.db"
          "--listen=127.0.0.1"
          "--port=${toString port}"
          "--enable-manager"
        ];
      };

      systemd.services.comfyui = {
        after = [ "comfyui-nvidia-uvm.service" ];
        requires = [ "comfyui-nvidia-uvm.service" ];
        wantedBy = lib.mkForce [ ];
        preStart = lib.mkForce "";
        environment = {
          HOME = dataDir;
          XDG_CACHE_HOME = "/run/comfyui/cache";
          MPLCONFIGDIR = "/run/comfyui/cache/matplotlib";
          TORCH_HOME = "${dataDir}/.cache/torch";
          HF_HOME = "${dataDir}/.cache/huggingface";
        };
        serviceConfig = {
          User = lib.mkForce flakeConfig.flake.meta.user.username;
          Group = lib.mkForce "users";
          WorkingDirectory = dataDir;
          ReadWritePaths = [ dataDir ];
          PrivateUsers = lib.mkForce false;
          Restart = lib.mkForce "no";
          RuntimeDirectory = "comfyui";
          RuntimeDirectoryMode = lib.mkForce "0755";
        };
      };

      systemd.services.comfyui-nvidia-uvm = {
        description = "Load NVIDIA UVM for ComfyUI";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.kmod}/bin/modprobe nvidia_uvm";
        };
      };

      environment.systemPackages = [ startComfyUI ];

      home-manager.sharedModules = [
        flakeConfig.flake.modules.homeManager."services/comfyui"
      ];
    };

  flake.modules.homeManager."services/comfyui" =
    { pkgs, ... }:
    let
      comfyuiIcon = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/comfyui-color.png";
        hash = "sha256-gpLSBehGjtjPXRmURN5aFmCPWE5RIIZaRlcH2bY4eNg=";
      };
    in
    {
      xdg.desktopEntries = {
        comfyui = {
          name = "ComfyUI";
          exec = "comfyui-start";
          icon = "${comfyuiIcon}";
          type = "Application";
          categories = [ "Graphics" ];
          startupNotify = false;
          terminal = false;
        };
      };
    };
}
