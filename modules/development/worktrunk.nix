{ inputs, ... }:
{
  flake.modules.homeManager.worktrunk =
    { pkgs, ... }:
    {
      imports = [ inputs.worktrunk.homeModules.default ];

      programs.worktrunk = {
        enable = true;
        package = pkgs.worktrunk;
      };
    };
}
