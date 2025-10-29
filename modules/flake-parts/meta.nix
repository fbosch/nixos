{ ... }:

{
  flake.meta = {
    user = {
      name = "fbb";
      fullName = "Frederik Bosch";
      home = "/home/fbb";
    };
    
    timezone = "Europe/Copenhagen";
    
    locale = {
      default = "en_DK.UTF-8";
      extra = {
        LC_ADDRESS = "da_DK.UTF-8";
        LC_IDENTIFICATION = "da_DK.UTF-8";
        LC_MEASUREMENT = "da_DK.UTF-8";
        LC_MONETARY = "da_DK.UTF-8";
        LC_NAME = "da_DK.UTF-8";
        LC_NUMERIC = "da_DK.UTF-8";
        LC_PAPER = "da_DK.UTF-8";
        LC_TELEPHONE = "da_DK.UTF-8";
        LC_TIME = "da_DK.UTF-8";
      };
    };
  };
}
