{ config, ... }:
{
  flake.modules.nixos."services/home-assistant" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      services.home-assistant = {
        enable = true;

        # Use a more recent version from unstable if needed
        # package = pkgs.unstable.home-assistant;

        # Configuration directory
        # This will store all Home Assistant data, configs, and databases
        configDir = "/var/lib/hass";

        # Extra packages to make available to Home Assistant
        # Add integrations and dependencies here as needed
        extraPackages =
          python3Packages: with python3Packages; [
            # Common integrations
            # aiohue  # Philips Hue
            # pymetno  # Met.no weather
            # gTTS  # Google Text-to-Speech
            # psycopg2  # PostgreSQL support
            isal
            zlib-ng
          ];

        # Extra components to enable
        # This pre-loads integrations for faster startup
        extraComponents = [
          "default_config" # Include default integrations
          "met" # Weather
          "esphome" # ESPHome integration
          "mqtt" # MQTT support
          # Add more as needed:
          # "hue"
          # "homekit"
          # "mobile_app"
          # "zha"  # Zigbee Home Automation
        ];

        # Configuration.yaml content
        # For complex configs, consider using configDir and managing files separately
        config = {
          default_config = { };

          http = {
            server_host = "0.0.0.0";
            server_port = 8123;
            use_x_forwarded_for = true;
            trusted_proxies = [
              "127.0.0.1"
              "192.168.1.2"
              "192.168.1.0/24"
            ];
          };

          homeassistant = {
            name = "Home";
            # Set your location for weather, sunrise/sunset, etc.
            # latitude = 52.520008;
            # longitude = 13.404954;
            # elevation = 34;
            # unit_system = "metric";
            # time_zone = "Europe/Berlin";
          };

          # Enable frontend
          frontend = { };

          # Enable automation UI
          automation = [ ];
          script = [ ];
          scene = [ ];
        };
      };

      # Open firewall for Home Assistant web interface
      networking.firewall.allowedTCPPorts = [ 8123 ];

      # Optional: Enable mDNS for .local domain discovery
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        publish = {
          enable = true;
          addresses = true;
          domain = true;
          workstation = true;
        };
      };

      # Ensure the service starts after network is ready
      systemd.services.home-assistant = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };
    };
}
