{
  flake.modules.nixos."hosts/rvn-pc/platform" =
    { config, lib, ... }:
    {
      services = {
        attic-client.enableSubstituter = false;

        # Avoid running two process-priority daemons with overlapping policies.
        ananicy.enable = lib.mkForce false;

        # Enable SSH for remote access
        openssh = {
          enable = true;
          startWhenNeeded = true;
        };

        samba = {
          enable = false;
          openFirewall = true;
          settings = {
            global = {
              "workgroup" = "WORKGROUP";
              "server string" = "rvn-pc";
              "netbios name" = "RVN-PC";
              "security" = "user";
              "map to guest" = "never";
              "hosts allow" = "127.0.0.1 192.168.122.0/24 10.0.2.0/24 192.168.1.0/24";
              "hosts deny" = "0.0.0.0/0";

              # Improve LAN transfer throughput with async I/O and zero-copy sends.
              "aio read size" = "1";
              "aio write size" = "1";
              "use sendfile" = "yes";

              # Allow SMB3 multichannel when clients/NICs support it.
              "server multi channel support" = "yes";
            };

            storage = {
              "path" = "/mnt/storage";
              "browseable" = "yes";
              "read only" = "no";
              "guest ok" = "no";
              "valid users" = config.flake.meta.user.username;
              "force user" = config.flake.meta.user.username;
              "create mask" = "0664";
              "directory mask" = "0775";
            };
          };
        };

        samba-wsdd = {
          enable = false;
          openFirewall = true;
        };
      };
    };
}
