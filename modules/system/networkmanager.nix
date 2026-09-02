{
  flake.modules.nixos = {
    "system/networkmanager" = { lib, ... }: {
      networking.networkmanager.enable = lib.mkDefault true;

      # NetworkManager ships initrd-only variants in the same package.
      # Disabled declarations mask those package units in stage 2 only.
      systemd.services = {
        NetworkManager-config-initrd.enable = false;
        NetworkManager-initrd.enable = false;
        NetworkManager-wait-online-initrd.enable = false;

        # Desktop hosts do not need to block boot on network-online.
        NetworkManager-wait-online.enable = lib.mkForce false;
      };
    };

    preservation = { config, lib, ... }: {
      config = lib.mkIf config.networking.networkmanager.enable {
        preservation.preserveAt."/persist".directories = [
          {
            directory = "/var/lib/NetworkManager";
            mode = "0755";
          }
          {
            directory = "/etc/NetworkManager/system-connections";
            mode = "0700";
          }
        ];
      };
    };
  };
}
