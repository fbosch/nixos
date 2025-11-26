{
  flake.modules.nixos.system = { pkgs, meta, ... }: {
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 7d --keep 15";
      flake = "/home/${meta.user.username}/nixos";
    };

    environment.systemPackages = with pkgs; [
      nh
      nix-output-monitor
    ];
  };
}
