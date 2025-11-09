{ lib, ... }: {
  flake.modules.homeManager.applications = {
    services.vicinae = {
      enable = true;
      autoStart = true;
    };

    # issue: 558
    systemd.user.services.vicinae = {
      Service.Environment = lib.mkForce [ "USE_LAYER_SHELL=0" ];
      Service.EnvironmentFile = lib.mkForce [ ];
    };
  };
}
