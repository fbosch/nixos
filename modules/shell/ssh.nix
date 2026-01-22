{ ... }:
{
  flake.modules.homeManager.shell = {
    programs.ssh = {
      enable = true;

      # Disable deprecated default config
      # Set default values explicitly in "*" matchBlock if needed
      enableDefaultConfig = false;

      matchBlocks = {
        # Default settings for all hosts
        "*" = {
          # Add any default SSH options you want here
          # For example:
          # serverAliveInterval = 60;
          # serverAliveCountMax = 3;
        };

        "rvn-srv" = {
          hostname = "192.168.1.46";
          user = "fbb";
        };
      };
    };
  };
}
