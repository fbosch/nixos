{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    let
      avifThumbnailer = pkgs.writeShellApplication {
        name = "avif-thumbnailer";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.imagemagick
          pkgs.libavif
        ];
        text = ''
          size="$1"
          input="$2"
          output="$3"
          tmp="$(mktemp --suffix=.png)"
          trap 'rm -f "$tmp"' EXIT

          avifdec "$input" "$tmp" >/dev/null
          magick "$tmp" -thumbnail "''${size}x''${size}" "$output"
        '';
      };
    in
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

        (writeTextFile {
          name = "avif-thumbnailer-entry";
          destination = "/share/thumbnailers/avif.thumbnailer";
          text = ''
            [Thumbnailer Entry]
            TryExec=${avifThumbnailer}/bin/avif-thumbnailer
            Exec=${avifThumbnailer}/bin/avif-thumbnailer %s %i %o
            MimeType=image/avif;image/avif-sequence;
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
