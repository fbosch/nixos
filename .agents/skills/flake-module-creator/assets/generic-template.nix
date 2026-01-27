_:
{
  flake.modules.generic."<NAME>" =
    { config
    , lib
    , ...
    }:
    {
      # Generic module - platform-agnostic
      # Importable into nixos, darwin, or homeManager modules

      # Define options for sharing
      options.<NAME> = {
      # Platform-agnostic options
      # Example:
      # constants = lib.mkOption {
      #   type = lib.types.attrs;
      #   default = {};
      #   description = "Shared constants";
      # };
      };

      config = {
        # Platform-agnostic configuration
        # Example:
        # <NAME>.constants = {
        #   domain = "example.com";
        #   timezone = "UTC";
        # };
      };
    };
}
