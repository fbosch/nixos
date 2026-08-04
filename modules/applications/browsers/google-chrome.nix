{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.google-chrome ];
    };
}
