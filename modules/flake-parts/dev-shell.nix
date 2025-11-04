{ inputs, ... }:
{
  perSystem = { pkgs, ... }: 
  let
    pre-commit-check = inputs.git-hooks.lib.${pkgs.system}.run {
      src = ./../..;
      hooks = {
        statix.enable = true;
        deadnix = {
          enable = true;
          settings.noLambdaPatternNames = true;
        };
        nixpkgs-fmt.enable = true;
      };
    };
  in
  {
    devShells.default = pkgs.mkShell {
      shellHook = ''
        ${pre-commit-check.shellHook}
      '';
      packages = with pkgs; [
        statix
        deadnix
        nixpkgs-fmt
      ];
    };
  };
}
