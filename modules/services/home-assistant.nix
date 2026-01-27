_: {
  flake.modules.nixos."services/home-assistant" =
    {
      config,
      lib,
      ...
    }:
    {
      config = {
        services = {
          home-assistant = {
            enable = lib.mkDefault true;

            # Configuration directory
            configDir = "/var/lib/hass";

            # Extra packages to make available to Home Assistant
            extraPackages =
              python3Packages: with python3Packages; [
                # Common integrations
                aiohue # Philips Hue
                aiohomekit # HomeKit Controller
                pyatv # Apple TV
                pychromecast # Chromecast / Google Cast
                pyicloud # Apple iCloud
                gtts # Google Text-to-Speech
                python-otbr-api # Thread support
                roombapy # iRobot Roomba
                isal
                zlib-ng
              ];

            # Extra components to enable
            extraComponents = [
              "default_config"
              "met"
              "esphome"
              "mqtt"
              "nest"
              "samsungtv"
              "cast"
              "wake_on_lan"
              "apple_tv"
              "icloud"
              "tuya"
              "pi_hole"
              "synology_dsm"
              "roomba"
            ];

            # Configuration.yaml content
            config = {
              default_config = { };

              http = {
                server_port = 8123;
                use_x_forwarded_for = true;
                trusted_proxies = [
                  "127.0.0.1"
                  "::1"
                  "192.168.1.0/24"
                ];
              };

              homeassistant = {
                name = "Home";
              };

              frontend = { };

              automation = "!include automations.yaml";
            };
          };

          # Optional: Enable mDNS for .local domain discovery
          avahi = {
            enable = true;
            nssmdns4 = true;
            publish = {
              enable = true;
              addresses = true;
              domain = true;
              workstation = true;
            };
          };
        };

        # Open firewall for Home Assistant web interface
        networking.firewall.allowedTCPPorts = [ 8123 ];

        # Ensure the service starts after network is ready
        systemd.services.home-assistant = {
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
        };
      };
    };
}
