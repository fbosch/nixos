{
  flake.modules.nixos.hardware = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      evemu
      evtest
    ];
  };
}
