_: {
  flake.modules.homeManager."files/wakatime" =
    { config
    , lib
    , ...
    }:
    let
      hasApiKey = lib.hasAttrByPath [ "sops" "placeholder" "wakapi-api-key" ] config;
      apiKey = lib.attrByPath [ "sops" "placeholder" "wakapi-api-key" ] "" config;
    in
    {
      config = lib.mkIf hasApiKey {
        home.file.".wakatime.cfg".text = ''
          [settings]
          api_url = https://wakapi.corvus-corax.synology.me/api
          api_key = ${apiKey}
        '';
      };
    };
}
