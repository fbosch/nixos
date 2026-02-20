{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      xdg.dataFile."nemo/actions/extract-to-folder.nemo_action".text =
        let
          extractScript = pkgs.writeShellApplication {
            name = "nemo-extract-to-folder";
            runtimeInputs = [ pkgs.p7zip ];
            text = builtins.readFile ./scripts/extract-to-folder.sh;
          };
        in
        ''
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
    };
}
