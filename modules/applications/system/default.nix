{
  flake.modules = {
    nixos.applications = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        hardinfo2
        resources
      ];
    };
  };
}
