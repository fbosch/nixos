{ inputs, ... }:
{
  flake.modules.homeManager.worktrunk =
    { pkgs, ... }:
    {
      imports = [ inputs.worktrunk.homeModules.default ];

      programs.worktrunk = {
        enable = true;
        package =
          if pkgs.stdenv.hostPlatform.isDarwin then
            pkgs.writeShellScriptBin "wt" ''
              exec /opt/homebrew/bin/wt "$@"
            ''
          else
            pkgs.worktrunk;
      };
    };
}
