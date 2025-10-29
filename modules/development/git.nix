{
  flake.modules.homeManager.development = { pkgs, ... }: {
    home.packages = with pkgs; [
      git-credential-manager
      lazygit
      delta
    ];
  };
}
