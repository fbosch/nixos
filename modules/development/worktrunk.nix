{ inputs, ... }:
{
  flake.modules.homeManager.worktrunk =
    { ... }:
    {
      imports = [ inputs.worktrunk.homeModules.default ];

      programs.worktrunk = {
        enable = true;
        enableBashIntegration = true;
      };
    };
}
