{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      extractScript = pkgs.writeShellApplication {
        name = "nemo-extract-to-folder";
        runtimeInputs = [ pkgs.p7zip ];
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

      convertScript = pkgs.writeShellApplication {
        name = "nemo-convert-image";
        runtimeInputs = [ pkgs.imagemagick ];
        text = builtins.readFile ./scripts/convert-image.sh;
      };

      mkConvertAction = ext: label: mimes: ''
        [Nemo Action]
        Active=true
        Name=Convert to ${label}
        Comment=Convert image to ${label} format
        Exec=${convertScript}/bin/nemo-convert-image ${ext} %F
        Icon-Name=image-x-generic
        Selection=single
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
          Selection=any
          Mimetypes=any;
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
