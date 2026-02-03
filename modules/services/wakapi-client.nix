_: {
  flake.modules.homeManager."services/wakapi-client" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.wakapi-client;
    in
    {
      options.services.wakapi-client = {
        apiUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://wakapi.corvus-corax.synology.me/api";
          description = "Wakapi API URL for the WakaTime client";
        };

        apiKey = lib.mkOption {
          type = lib.types.str;
          default = lib.attrByPath [ "sops" "placeholder" "wakapi-api-key" ] "" config;
          description = "Wakapi API key for the WakaTime client";
        };
      };

      config = {
        home.file.".wakatime.cfg".text = ''
          [settings]
          api_url = ${cfg.apiUrl}
          api_key = ${cfg.apiKey}
        '';
      };
    };
}
