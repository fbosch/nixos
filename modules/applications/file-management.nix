{
  flake.modules.nixos.applications = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      selectdefaultapplication
    ];
  };

  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      nemo-with-extensions
      loupe
      xdg-utils
    ];
  };
}
