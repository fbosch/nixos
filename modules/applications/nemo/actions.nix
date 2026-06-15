{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      extractScript = pkgs.writeShellApplication {
        name = "nemo-extract-to-folder";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs._7zz
          pkgs.unrar
          pkgs.zenity
        ];
        text = builtins.readFile ./scripts/extract-to-folder.sh;
      };

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
        "nemo/actions/extract-to-folder.nemo_action".text = ''
          [Nemo Action]
          Active=true
          Name=Extract Here (to folder)
          Comment=Extract archive into a folder named after the file
          Exec=${extractScript}/bin/nemo-extract-to-folder %F
          Icon-Name=package-x-generic
          Selection=single
          Quote=double
          Extensions=zip;7z;rar;tar;gz;bz2;xz;zst;cab;iso;tgz;tbz2;txz;
          Terminal=false
        '';

        "nemo/actions/extract-to-folder-with-password.nemo_action".text = ''
          [Nemo Action]
          Active=true
          Name=Extract Here (with password)
          Comment=Extract password-protected archive into a folder named after the file
          Exec=${extractScript}/bin/nemo-extract-to-folder --password %F
          Icon-Name=dialog-password
          Selection=single
          Quote=double
          Extensions=zip;7z;rar;tar;gz;bz2;xz;zst;cab;iso;tgz;tbz2;txz;
          Terminal=false
        '';

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
