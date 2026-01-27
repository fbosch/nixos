_: {
  flake.modules.nixos."system/<NAME>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      config = {
        # System configuration
        # Use lib.mkDefault for user-overridable values

        # Example: Kernel parameters
        # boot.kernel.sysctl = {
        #   "vm.swappiness" = lib.mkDefault 60;
        #   "net.ipv4.tcp_fastopen" = lib.mkDefault 3;
        # };

        # Example: systemd configuration
        # systemd.extraConfig = ''
        #   DefaultTimeoutStopSec=30s
        # '';

        # Example: environment packages
        # environment.systemPackages = with pkgs; [
        #   # System tools
        # ];

        # Example: environment variables
        # environment.variables = {
        #   VARIABLE_NAME = lib.mkDefault "value";
        # };
      };
    };
}
