{ config, pkgs, lib, inputs, ... }:

{
  programs.bash.enable = true;
  programs.zen-browser.enable = true;
  programs.neovim.enable = true;
  programs.fzf.enable = true;
  programs.bat.enable = true;
  programs.gpg = {
    enable = true;
  };
  programs.git = { 
    enable = true;
    extraConfig.credential.helper = "manager";
    extraConfig.credential."https://github.com".username = "fbosch";
    extraConfig.credential.credentialStore = "gpg";
  };
 # programs.elephant.enable = true;
  programs.walker = {
    enable = true;
    runAsService = true;
  };
}
