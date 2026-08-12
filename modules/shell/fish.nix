let
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      fish
      dash
      starship
      zoxide
      atuin
      navi
      tealdeer
    ];
  };
in
{
  flake.modules = {
    nixos.shell =
      { pkgs, ... }:
      {
        imports = [ systemPackages ];
        environment.shells = [
          pkgs.fish
          pkgs.dash
        ];
      };

    darwin.shell =
      { pkgs, ... }:
      {
        imports = [ systemPackages ];

        programs.fish = {
          enable = true;
          useBabelfish = true;
          package = pkgs.fish;
        };
      };
  };
}
