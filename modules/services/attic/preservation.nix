{
  flake.modules.nixos.preservation =
    { config
    , lib
    , options
    , ...
    }:
    {
      config =
        lib.mkIf
          (
            lib.hasAttrByPath [
              "services"
              "attic"
              "watchStore"
              "enable"
            ]
              options
            && config.services.attic.watchStore.enable
          )
          {
            preservation.preserveAt."/persist".directories = [
              {
                directory = "/var/lib/private/attic-upload";
                mode = "0750";
              }
            ];
          };
    };
}
