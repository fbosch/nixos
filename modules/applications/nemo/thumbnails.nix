{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = with pkgs; [
        # Image format libraries
        libwebp
        libjpeg
        libavif
        libheif
        webp-pixbuf-loader # WebP gdk-pixbuf loader + thumbnailer

        # Thumbnail generation
        gnome-desktop # Required for Nemo thumbnail generation
        gdk-pixbuf # Image loading library
        ffmpegthumbnailer # Video thumbnails
        poppler-utils # PDF thumbnails

        # HEIF thumbnailer registration. libheif ships heif-thumbnailer but no
        # gdk-pixbuf loader, so the generic gdk-pixbuf-thumbnailer.thumbnailer
        # does not cover image/heic or image/heif. Must be in systemPackages so
        # the file lands under /run/current-system/sw/share/thumbnailers/ which
        # is on XDG_DATA_DIRS; environment.etc puts it in /etc/share/ which is
        # not searched.
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

      # Force Nemo's thumbnail size limit to 10 MB via a system-level dconf
      # override. Nemo's GSettings schema lives in a versioned subdirectory not
      # merged into the system profile, so the user dconf value is ignored and
      # Nemo falls back to its compiled-in 1 MB default. A system profile
      # override bypasses schema lookup and is always read.
      programs.dconf.profiles.user.databases = [
        {
          settings."org/nemo/preferences".thumbnail-limit = lib.gvariant.mkUint64 10485760;
        }
      ];
    };
}
