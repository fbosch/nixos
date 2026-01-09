{
  flake.modules.homeManager.shell =
    { pkgs, ... }:
    {
      programs.bat.enable = true;

      home.packages = with pkgs; [
        glow # Markdown renderer
      ];
    };
}
