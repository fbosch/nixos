{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = with pkgs; [
        libwebp
        libjpeg
        libavif
        libheif
        webp-pixbuf-loader

        gnome-desktop
        gdk-pixbuf
        ffmpegthumbnailer
        poppler-utils

        # libheif ships heif-thumbnailer but no gdk-pixbuf loader, so it must
        # be registered manually. Installed via systemPackages so it lands in
        # /run/current-system/sw/share/thumbnailers/ (on XDG_DATA_DIRS).
        (writeTextFile {
          name = "heif-thumbnailer-entry";
          destination = "/share/thumbnailers/heif.thumbnailer";
          text = ''
            [Thumbnailer Entry]
            TryExec=${libheif}/bin/heif-thumbnailer
            Exec=${libheif}/bin/heif-thumbnailer -s %s %i %o
            MimeType=image/heic;image/heif;image/heic-sequence;image/heif-sequence;
          '';
        })
      ];

      # Nemo's GSettings schema isn't merged into the system profile, so the
      # user dconf value for thumbnail-limit is ignored. A system-level dconf
      # profile override bypasses schema lookup and is always read.
      programs.dconf.profiles.user.databases = [
        {
          settings."org/nemo/preferences".thumbnail-limit = lib.gvariant.mkUint64 10485760;
        }
      ];
    };
}
