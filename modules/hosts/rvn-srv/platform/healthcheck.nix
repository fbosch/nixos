{
  flake.modules.nixos."hosts/rvn-srv/platform" =
    { pkgs, ... }:
    let
      systemHealthcheck = pkgs.writeShellApplication {
        name = "system-healthcheck";
        runtimeInputs = with pkgs; [
          bash
          coreutils
          curl
          gawk
          gnugrep
          podman
          procps
          systemd
          util-linux
        ];
        text = builtins.readFile ./healthcheck.sh;
      };
    in
    {
      environment.systemPackages = [ systemHealthcheck ];
    };
}
