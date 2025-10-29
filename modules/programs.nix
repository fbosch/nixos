{
  flake.modules.homeManager.programs = { pkgs, ... }: {
    programs = {
      bash = {
        enable = true;
        initExtra = ''
          if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
          then 
            shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
            exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
          fi
        '';
      };

      git = {
        enable = true;
        extraConfig = {
          credential = {
            helper = "manager";
            "https://github.com".username = "fbosch";
            credentialStore = "gpg";
          };
        };
      };

      fzf.enable = true;
      bat.enable = true;
      gpg.enable = true;
      neovim.enable = true;
    };

    services.gpg-agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-curses;
      enableSshSupport = true;
    };

    services.vicinae.enable = true;
  };
}
