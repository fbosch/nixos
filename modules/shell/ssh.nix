{ config, ... }:
{
  flake.modules.homeManager.shell =
    { config, ... }:
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        matchBlocks = {
          "pc" = {
            hostname = "192.168.1.169";
            user = "fbb";
            identityFile = config.sops.secrets.ssh-private-key.path;
          };
          "srv" = {
            hostname = "192.168.1.46";
            user = "fbb";
            identityFile = config.sops.secrets.ssh-private-key.path;
          };
        };
      };

      # Enable and start ssh-agent
      services.ssh-agent.enable = true;
    };
}
