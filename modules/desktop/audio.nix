{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    security.rtkit.enable = true;

    environment.systemPackages = with pkgs; [
      wiremix
    ];

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
  };
}
