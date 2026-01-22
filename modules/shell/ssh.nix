{ ... }:
{
  flake.modules.homeManager.shell = {
    programs.ssh = {
      enable = true;

      matchBlocks = {
        "rvn-srv" = {
          hostname = "192.168.1.46";
          user = "fbb";
        };
      };
    };
  };
}
