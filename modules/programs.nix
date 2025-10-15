{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  programs.bash = {
    enable = true;
    initExtra = ''
             if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
             then 
             	  shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
      	  exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
             fi
    '';
  };
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
  programs.hyprshell = {
    enable = true;
    systemd.args = "-v";
    settings = {
      windows = {
        enable = true;
        overview = {
          enable = true;
          key = "super_l";
          modifier = "super";
          launcher = {
            max_items = 6;
          };
        };
        switch.enable = true;
      };
    };
  };
}
