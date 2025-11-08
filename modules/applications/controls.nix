{
  flake.modules.nixos.applications = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      selectdefaultapplication
    ];
  };
}
