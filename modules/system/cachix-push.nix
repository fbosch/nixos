{ lib
, config
, pkgs
, ...
}:
let
  hasSops = lib.hasAttrByPath [ "sops" "secrets" ] config;
in
{
  flake.modules.nixos.system = {
    nix.settings = lib.mkIf hasSops {
      post-build-hook = "/etc/nix/post-build-hook.sh";
    };

    sops.secrets."cachix-auth-token" = lib.mkIf hasSops {
      mode = "0400";
    };

    sops.templates."cachix-env" = lib.mkIf hasSops {
      content = "CACHIX_AUTH_TOKEN=${config.sops.placeholder."cachix-auth-token"}\n";
      mode = "0400";
    };

    environment.etc."nix/post-build-hook.sh" = lib.mkIf hasSops {
      mode = "0550";
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        env_file="${config.sops.templates."cachix-env".path}"
        if [ ! -f "${config.sops.templates."cachix-env".path}" ]; then
          exit 0
        fi

        # shellcheck disable=SC1090
        source "${config.sops.templates."cachix-env".path}"

        if [ -z "''${CACHIX_AUTH_TOKEN:-}" ]; then
          exit 0
        fi

        paths=()
        while IFS= read -r path; do
          if [ -n "$path" ]; then
            paths+=("$path")
          fi
        done

        if [ ''${#paths[@]} -eq 0 ]; then
          exit 0
        fi

        exec ${pkgs.cachix}/bin/cachix push fbosch "''${paths[@]}"
      '';
    };
  };
}
