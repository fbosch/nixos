{
  flake.modules.homeManager.development.git = { pkgs, ... }: {
    home.packages = with pkgs; [
      git-credential-manager
      lazygit
      delta
    ];
  };
}
