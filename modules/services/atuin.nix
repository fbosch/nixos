_: {
  flake.modules.nixos."services/atuin" =
    { config
    , lib
    , ...
    }:
    let
      port = 8086;
    in
    {
      config = lib.mkMerge [
        {
          services.atuin = {
            enable = lib.mkDefault true;
            host = lib.mkDefault "0.0.0.0";
            port = lib.mkDefault port;
            openFirewall = lib.mkDefault true;
            openRegistration = lib.mkDefault true;
            database.createLocally = lib.mkDefault true;
          };
        }
      ];
    };
}
