{
  flake.modules.nixos."hardware/fancontrol" =
    { pkgs, ... }:
    {
      programs.coolercontrol.enable = true;
    };
}
