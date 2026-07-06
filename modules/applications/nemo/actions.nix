{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      shredScript = pkgs.writeShellApplication {
        name = "nemo-shred-files";
        runtimeInputs = [
          pkgs.zenity
          pkgs.coreutils
        ];
        text = builtins.readFile ./scripts/shred-files.sh;
      };

      makeExecutableScript = pkgs.writeShellApplication {
        name = "nemo-make-executable";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.polkit
          pkgs.zenity
        ];
        text = builtins.readFile ./scripts/make-executable.sh;
      };

      copyPathScript = pkgs.writeShellApplication {
        name = "nemo-copy-path";
        runtimeInputs = [ pkgs.wl-clipboard ];
        text = ''
          printf '%s' "$1" | wl-copy
        '';
      };

      convertScript = pkgs.writeShellApplication {
        name = "nemo-convert-image";
        runtimeInputs = [ pkgs.imagemagick ];
        text = builtins.readFile ./scripts/convert-image.sh;
      };

      launchWithFaugusScript = pkgs.writeShellApplication {
        name = "nemo-launch-with-faugus";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.faugus-launcher
          pkgs.gamemode
          pkgs.mangohud
          pkgs.umu-launcher
          pkgs.zenity
        ];
        text = builtins.readFile ./scripts/launch-with-faugus.sh;
      };

      mkConvertAction = ext: label: mimes: ''
        [Nemo Action]
        Active=true
        Name=Convert to ${label}
        Comment=Convert image to ${label} format
        Exec=${convertScript}/bin/nemo-convert-image ${ext} %F
        Icon-Name=image-x-generic
        Selection=single
        Quote=double
        Mimetypes=${mimes};
        Terminal=false
      '';

    in
    {
      xdg.dataFile = {
        "nemo/actions/shred-files.nemo_action".text = ''
          [Nemo Action]
          Active=true
          Name=Shred
          Comment=Securely delete file(s) beyond recovery
          Exec=${shredScript}/bin/nemo-shred-files %F
          Icon-Name=edit-delete
          Selection=notnone
          Quote=double
          Mimetypes=any;
          Terminal=false
        '';

        "nemo/actions/make-executable.nemo_action".text = ''
          [Nemo Action]
          Active=true
          Name=Make Executable
          Comment=Mark selected file(s) as executable using administrator authentication
          Exec=${makeExecutableScript}/bin/nemo-make-executable %F
          Icon-Name=system-run
          Selection=notnone
          Quote=double
          Extensions=nodirs;
          Terminal=false
        '';

        "nemo/actions/copy-path.nemo_action".text = ''
          [Nemo Action]
          Active=true
          Name=Copy Path
          Comment=Copy the selected item path to the clipboard
          Exec=${copyPathScript}/bin/nemo-copy-path %F
          Icon-Name=edit-copy
          Selection=s
          Quote=double
          Extensions=any;
          Terminal=false
        '';

        "nemo/actions/copy-directory-path.nemo_action".text = ''
          [Nemo Action]
          Active=true
          Name=Copy Path
          Comment=Copy the current directory path to the clipboard
          Exec=${copyPathScript}/bin/nemo-copy-path %P
          Icon-Name=edit-copy
          Selection=none
          Quote=double
          Extensions=any;
          Terminal=false
        '';

        "nemo/actions/launch-with-faugus.nemo_action".text = ''
          [Nemo Action]
          Active=true
          Name=Launch with Faugus
          Comment=Choose a Proton runtime and launch this executable or shell script with Faugus
          Exec=${launchWithFaugusScript}/bin/nemo-launch-with-faugus %F
          Icon-Name=faugus-launcher
          Selection=single
          Quote=double
          Extensions=exe;sh;bash;
          Terminal=false
        '';

        "nemo/actions/convert-to-png.nemo_action".text =
          mkConvertAction "png" "PNG"
            "image/jpeg;image/webp;image/heic;image/heif";
        "nemo/actions/convert-to-jpg.nemo_action".text =
          mkConvertAction "jpg" "JPEG"
            "image/png;image/webp;image/heic;image/heif";
        "nemo/actions/convert-to-webp.nemo_action".text =
          mkConvertAction "webp" "WebP"
            "image/png;image/jpeg;image/heic;image/heif";
      };
    };
}
