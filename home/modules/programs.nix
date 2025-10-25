{ pkgs, config, ... }:
{
  nix.settings = {
    builders-use-substitutes = true;
    extra-substituters = [ "https://anyrun.cachix.org" ];
    extra-trusted-public-keys = [ "anyrun.cachix.org-1:pqBobmOjI7nKlsUMV25u9QHa9btJK65/C8vnO3p346s=" ];
  };

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
      settings.credential = {
        helper = "manager";
        "https://github.com".username = "fbosch";
        credentialStore = "gpg";
      };
    };

    fzf.enable = true;
    bat.enable = true;
    gpg.enable = true;
    neovim.enable = true;
  };

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-curses;
    enableSshSupport = true;
  };

  services.vicinae.enable = true;
}
