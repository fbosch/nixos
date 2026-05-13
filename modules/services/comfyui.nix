{ inputs, config, ... }:
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
      nvidiaNamespaceShim = pkgs.writeTextDir "nvidia/__init__.py" "";
      runtimeCompatibleComfyUI = pkgs.runCommand "comfy-ui-runtime-compatible" { } ''
        mkdir -p "$out"
        cp -RL ${pkgs.comfy-ui-cuda}/. "$out/"
        chmod -R u+w "$out"

        for bin in "$out/bin/comfy-ui" "$out/bin/comfyui"; do
          substituteInPlace "$bin" \
            --replace-fail \
              "          'import sys' \\" \
              "          'import sys' \\
          'import importlib' \\
          ' ' \\
          'base_dir = os.environ.get(\"COMFYUI_BASE_DIR\")' \\
          'if base_dir:' \\
          '    try:' \\
          '        folder_paths = importlib.import_module(\"folder_paths\")' \\
          '        folder_paths.__file__ = os.path.join(base_dir, \"folder_paths.py\")' \\
          '    except Exception:' \\
          '        pass' \\"
        done
      '';
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
      imports = [ inputs.comfyui-nix.nixosModules.default ];

      boot.kernelModules = [ "nvidia_uvm" ];

      services.comfyui = {
        enable = true;
        gpuSupport = "cuda";
        package = runtimeCompatibleComfyUI;
        enableManager = true;

        inherit dataDir port;
        listenAddress = "127.0.0.1";
        openFirewall = false;

        user = flakeConfig.flake.meta.user.username;
        group = "users";
        createUser = false;

        requiresMounts = [ "mnt-storage.mount" ];

        environment = {
          HOME = dataDir;
          PYTHONPATH = "${nvidiaNamespaceShim}";
          XDG_CACHE_HOME = "${dataDir}/.cache";
          MPLCONFIGDIR = "${dataDir}/.cache/matplotlib";
        };
      };

      systemd.services.comfyui = {
        after = [ "comfyui-nvidia-uvm.service" ];
        requires = [ "comfyui-nvidia-uvm.service" ];
        wantedBy = lib.mkForce [ ];
        serviceConfig.Restart = lib.mkForce "no";
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
