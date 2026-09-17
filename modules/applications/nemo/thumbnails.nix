{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    let
      blpMimeType = pkgs.writeTextFile {
        name = "blp-mime-type";
        destination = "/share/mime/packages/blp.xml";
        text = ''
          <?xml version="1.0" encoding="UTF-8"?>
          <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
            <mime-type type="image/x-blp">
              <comment>Blizzard Picture</comment>
              <glob pattern="*.blp" weight="80"/>
              <magic priority="50">
                <match type="string" offset="0" value="BLP1"/>
                <match type="string" offset="0" value="BLP2"/>
              </magic>
            </mime-type>
          </mime-info>
        '';
      };
      rpgMakerMimeType = pkgs.writeTextFile {
        name = "rpg-maker-encrypted-image-mime-type";
        destination = "/share/mime/packages/rpg-maker-encrypted-image.xml";
        text = ''
          <?xml version="1.0" encoding="UTF-8"?>
          <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
            <mime-type type="image/x-rpg-maker-encrypted">
              <comment>Encrypted RPG Maker image</comment>
              <glob pattern="*.rpgmvp" weight="80"/>
              <glob pattern="*.png_" weight="80"/>
            </mime-type>
          </mime-info>
        '';
      };
      rpgMakerImageDecrypter = pkgs.writeShellApplication {
        name = "rpg-maker-image-decrypter";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.local.rpgmasd
        ];
        text = builtins.readFile ./scripts/decrypt-rpg-maker-image.sh;
      };
      rpgMakerThumbnailer = pkgs.writeShellApplication {
        name = "rpg-maker-thumbnailer";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.imagemagick
        ];
        text = ''
          size="$1"
          input="$2"
          output="$3"
          tmp="$(mktemp --suffix=.png)"
          trap 'rm -f "$tmp"' EXIT

          ${rpgMakerImageDecrypter}/bin/rpg-maker-image-decrypter "$input" "$tmp"
          magick "$tmp" -thumbnail "''${size}x''${size}" "PNG:$output"
        '';
      };
      blpThumbnailer = pkgs.writeShellApplication {
        name = "blp-thumbnailer";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.imagemagick
          pkgs.local."blp-conv"
        ];
        text = ''
          size="$1"
          input="$2"
          output="$3"
          tmp="$(mktemp --suffix=.png)"
          trap 'rm -f "$tmp"' EXIT

          blp-conv "$input" "$tmp"
          magick "$tmp" -thumbnail "''${size}x''${size}" "PNG:$output"
        '';
      };
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
        blpMimeType
        rpgMakerMimeType
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

        (writeTextFile {
          name = "blp-thumbnailer-entry";
          destination = "/share/thumbnailers/blp.thumbnailer";
          text = ''
            [Thumbnailer Entry]
            TryExec=${blpThumbnailer}/bin/blp-thumbnailer
            Exec=${blpThumbnailer}/bin/blp-thumbnailer %s %i %o
            MimeType=image/x-blp;
          '';
        })

        (writeTextFile {
          name = "rpg-maker-thumbnailer-entry";
          destination = "/share/thumbnailers/rpg-maker.thumbnailer";
          text = ''
            [Thumbnailer Entry]
            TryExec=${rpgMakerThumbnailer}/bin/rpg-maker-thumbnailer
            Exec=${rpgMakerThumbnailer}/bin/rpg-maker-thumbnailer %s %i %o
            MimeType=image/x-rpg-maker-encrypted;
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
