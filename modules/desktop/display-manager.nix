_: {
  flake.modules.nixos.desktop =
    { config, ... }:
    let
      nixosVersion = "${config.system.nixos.release} ${config.system.nixos.codeName}";
      linuxVersion = "Linux ${config.boot.kernelPackages.kernel.version}";
    in
    {
      services.displayManager.ly = {
        enable = true;
        x11Support = true;
        settings = {
          initial_info_text = "${nixosVersion} (${linuxVersion})";
          text_in_center = true;
          margin_box_h = 10;
          margin_box_v = 2;
          input_len = 46;
          hide_key_hints = true;
          edge_margin = 1;
        };
      };
    };
}
