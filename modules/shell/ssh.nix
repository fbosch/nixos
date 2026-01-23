_:
{
  flake.modules.homeManager.shell = {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = {
        "pc" = {
          hostname = "192.168.1.169";
          user = "fbb";
        }
        "srv" = {
          hostname = "192.168.1.46";
          user = "fbb";
        };
      };
    };
  };
}
