{
  flake.modules.homeManager.applications =
    { config, pkgs, ... }:
    let
      externalApplication = pkgs.writeShellApplication {
        name = "external-application";
        runtimeInputs = with pkgs; [
          flatpak
          media-downloader
          mpv
          xdg-utils
        ];
        text = ''
          request="''${1#x-external-application://}"
          target="''${request%%/*}"
          url="''${request#*/}"

          case "$url" in
            http://* | https://*) ;;
            *) exit 1 ;;
          esac

          case "$target" in
            zen) exec xdg-open "$url" ;;
            floorp) exec flatpak run one.ablaze.floorp "$url" ;;
            media-downloader) exec media-downloader "$url" ;;
            mpv) exec mpv "$url" ;;
            helium) exec helium-browser "$url" ;;
            *) exit 1 ;;
          esac
        '';
      };
      nativeHost = pkgs.writeText "external-application-native-host" ''
        #!/usr/bin/env python3
        import json
        import struct
        import subprocess
        import sys
        from urllib.parse import urlparse

        MAX_MESSAGE_SIZE = 65_536
        XDG_OPEN = "${pkgs.xdg-utils}/bin/xdg-open"
        PREFIX = "x-external-application://"
        TARGETS = {"zen", "floorp", "media-downloader", "mpv", "helium"}

        def read_message():
            header = sys.stdin.buffer.read(4)
            if len(header) != 4:
                raise ValueError
            length = struct.unpack("@I", header)[0]
            if length > MAX_MESSAGE_SIZE:
                raise ValueError
            body = sys.stdin.buffer.read(length)
            if len(body) != length:
                raise ValueError
            return json.loads(body.decode("utf-8"))

        def write_message(response):
            body = json.dumps(response, separators=(",", ":")).encode("utf-8")
            sys.stdout.buffer.write(struct.pack("@I", len(body)))
            sys.stdout.buffer.write(body)
            sys.stdout.buffer.flush()

        def valid_url(value):
            if not isinstance(value, str) or any(
                char.isspace() or ord(char) < 32 or char == "\\" for char in value
            ) or not value.startswith(PREFIX):
                return False
            target, separator, url = value.removeprefix(PREFIX).partition("/")
            if not separator or target not in TARGETS:
                return False
            parsed = urlparse(url)
            try:
                port = parsed.port
            except ValueError:
                return False
            return (
                parsed.scheme in {"http", "https"}
                and bool(parsed.hostname)
                and (port is None or port > 0)
            )

        def response_for(request):
            if request == {"cmd": "env"}:
                return {"env": {}}
            if not isinstance(request, dict) or set(request) != {
                "cmd", "command", "arguments", "stdin", "properties"
            }:
                return {"code": 126, "stdout": "", "stderr": "request denied"}
            arguments = request.get("arguments")
            if (
                request.get("cmd") != "exec"
                or request.get("command") != XDG_OPEN
                or not isinstance(arguments, list)
                or len(arguments) != 1
                or request.get("stdin") != []
                or request.get("properties") != {}
                or not valid_url(arguments[0])
            ):
                return {"code": 126, "stdout": "", "stderr": "request denied"}
            try:
                completed = subprocess.run(
                    [XDG_OPEN, arguments[0]],
                    check=False,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=15,
                )
            except FileNotFoundError:
                return {"code": 127, "stdout": "", "stderr": "xdg-open unavailable"}
            except subprocess.TimeoutExpired:
                return {"code": 124, "stdout": "", "stderr": "xdg-open timed out"}
            if completed.returncode:
                return {"code": completed.returncode, "stdout": "", "stderr": "xdg-open failed"}
            return {"code": 0, "stdout": "", "stderr": ""}

        try:
            write_message(response_for(read_message()))
        except (UnicodeDecodeError, ValueError, json.JSONDecodeError):
            raise SystemExit(64)
      '';
      nativeHostManifest = pkgs.writeText "com.add0n.node.json" (
        builtins.toJSON {
          name = "com.add0n.node";
          description = "Restricted External Application Launcher host";
          path = "${config.home.homeDirectory}/.mozilla/native-messaging-hosts/com.add0n.node";
          type = "stdio";
          allowed_extensions = [ "{65b77238-bb05-470a-a445-ec0efe1d66c4}" ];
        }
      );
      icons = {
        # Official assets from each application's upstream project.
        zen = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAPFBMVEX///8gICBVVFGJiIG9vLLY1sry8OPl49eWlY5IR0XLyb9iYV0uLS06OjmjoprX1stHR0Vvbml8e3Wwr6ZJ3c8dAAAAAXRSTlMAQObYZgAAAWJJREFUOMuFUwmOxCAMayAklLPM/v+va+hFZ7UzSJUKdoiTmGXBov/WsnyEDwbRZ8a0MZadiLJfZ8YNs1wrxD+E5BHrY8afKVWkpCchBVGbrjCr4vJMAF5xYAo0hIL7c5WQJoLveL5EIBqMchOMSKZVkQXXbK2KrpRVzEVgsf3gFAbBmskKn4RVKpET30tV4UZUAKb9imUoKBSlJrLVJIrV7qDvIYPA2BVp1OrIkarB/QXKwkFQSAyyEcezp5TFURI9CCLHd3ZV77MHQc9WyhvBIUX/2Ox4ZBQWphQsESItGbeLdNA7RPJVpscOCayLGKZDmQ4xd5kD5N77xvCLGbPpmc1bq/3Z6tJb/eqka1g42OCBBrNlmEG3HtDmce8TPhZj4+Zxd8N0B8USYIaC1MDrbJgera/LcQlZ6sNyQ1iPTd20gOXnzbRYrd62P3v6IKAYD7+IBm+mw+9P7/vj/cQA+Av6sw+Ly7ppHgAAAABJRU5ErkJggg==";
        floorp = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAABqlBMVEX///9lB+hgB+hzBehxBehtA+ZyButsBulsBuhoC+WJQ+WbXuibXudpBuhlBeahaunw6vr49vxWCeh6LePh1Pb6+v1jB+mzjez3+Py1kO1bB+Dm3/f19fvi4/PHweG5puhnGuJcB+isptM7IpM+HJxbCOZbBuaMWeXq6/bu7/ihl80sEYoqD4k5CalcCOlbCOjIue8tDZBNCMtFCuhVB+eYdOadk8smC4YoDYdLCuhUCelsMOLLxui9uN15arZ1ZrSDXdhkIuRUCehSCOWZeOff4PJQCehMCOaXd+bd3/FMCupjMOLHwOxECulDDOSIbOPX2e7Z2u+up9l8XOM/C+g8C+lMIOGWjsYyG4gvFoY/Fss6CuZnVeDMzerU1e2OhcEiCHoqCKc1DOg1DOk7FeKckeWLgr4gB3UwC9IsDeMtDOZUPOC8vOfP0ewfB3MjCrcOEOgrDekqEOOBd+GGfrkdBm4gCI0jDugjDukiDec8K+Ctq+QgCW8fDugbD+l+d8YeC5gcCJccCq4ZDuIIEOgUD+gcFORBO+A2MN8RD+gSEOgNEOgNEOsIEeisRWu1AAAAAXRSTlMAQObYZgAAAd1JREFUOMut0/1f0kAcB3BE5wnifL6UNkETBB/OCopcZj5NRJ1SilYIlSuR+cRKEzUxlVVq/s/d3Nhu+Kvv/bbP5/W67e57Ntv9qbBXGuxVd+IqqtqCKq9Q1YAiAEBZ8xoAHM5ajcvlcjoAqCHzOgDo+oZGQ0M9DUAdUWgCdHNLK6GlmQZNxA9A6HjQ2tZGNNodEFYYBTeknQ8Zhu0webwQuku5HXZ6PQzDdD0ydbshhHa94Ov09wSCQaa3T9ePDfgQ8mn5IPJ7HwcDgaBRUBtPniKEBtU8hFD4WUD1vD8SeREpGXD7EQrhwhAXfjl8W3g18po0OhZGQ7gwzk1MsiZex/Ls5AQ3jgtTXHQav47FYrwVOx3lptQlZqKzczETrz64z8/NRmfUJUKCML8Qf4MNd5HeLs4LgvqRtiUhseyJYyvv3pv6PuB8SduIZCK5moqn4x8/ET4nE4mkvpNrovjlazqdXjfSTCayIYriWukwspK0ubW9vZ7R7GC7kiRljdPMyfK376nU3m2k2v+RlWU5Zw7EQf7w6Di193Nft7N7mM8fEBN1UigUVrdOf53pzi/wixNyKIsF5fefvxclCs6L1rG+vFIU5YpwWXYvctf/LK5ztnI3RcLNvdxmzX9soqfWlDJ13AAAAABJRU5ErkJggg==";
        mediaDownloader = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAA21BMVEX///8lt9MludUrudRMxNtvz+I7vtej4ezt+fz9/v4os800nLE3mKw+n7Oz4eq76OFwz8Axk6ctkKMslalbXWBaW16OkJKE1sgPrpVPUVRBQUI+P0A9Q0a7u7sVsJezs7Q9PT4tjqHBwcOe3tRFwa2rq62g39UktZ6cnJ17fH7r7Oyu5NssuKFlZWb09PTF7eaJiYvHyMnj5OTh399zc3RVVVhQUFJNTU5Co7Z3eHpoaGk6nK5qy97z+vzl5+hiyd1ayN1kzOCr3eYetdKHztyO1ePA4ejl6usyu9V1mh03AAAAAXRSTlMAQObYZgAAAVdJREFUOMuVk+l2gjAQRg0IOopLK6jVimm1LriWtnZTI271/Z+ogSQSKLan9wcn8N2TzCEzqZQE4qQSoYGiIPFMiFnK8NexXI65Es3RD2QjKZeNMFfTmpZW40aQKz56JguQzejBS2j4Qi5vGEahCKVyuQTFgnF1XckJwc+VvGmaVhWgVq/XAKo3jeZtReFGIBimZVktKtg2FdoNjJt3ZwEJ4R46XdvudqCNueD/LlZiIDxAr2/b/R4MzgLdQhKGDozG4xE4k4gQHmENpjCbwXSOLwnm/NF9aj03QwFFBct6Wbw2MI4KrAaWL3BItMi3oc/7xyTkUxbQcspxXbFaivsKTtKAsVqvV3ypifYMtiDis+MIlSDpLpC6IR4hZOtQtp7nEW+jIvk6Gbu9S9nvYh1zFvTD8YtyPOhJLUU5Ec7pclP+p61jg4F+H5y/R08ML02U5OG9OP7firQsXXWMkKUAAAAASUVORK5CYII=";
        mpv = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAABX1BMVEX///+wsLHHx8e5qL6slrKmjqyghqesmbGurq7FwMdySXtqO3NnOHBjNGyZf5/j4+NkO2uYgJ7i3uSBW4lVKl1AG0c4Ez81ETs+GUVNIlVbLGNdNGV2VH3l4ed5T4E8FENwS3jt7e1/WYcxDzdIHE9XK2BAFkdCF0lLHVKCaYja1dxcPGNFG0z29vaZfJ+6rr3f2+Cpm61QJlfw7vBsQXV3YH3d2d7SzdRlSGzKvc3V0djLxc2gl6Lw8PDBtcR+V4a+s8LOydCXhJyLc5Hz8/ObfqJIIE9LKFLGu8mAYYfDvca+ucBTJFuBa4aUdpuIao5/aYWFbYvHwsm6tbxXJ2B8YYOnkK10Vnuxq7OLeo/n5+e1qrhlRGyworOKdY+fl6FfMGispa6MbZOAaoaej6KOepO8vLzV1dVYMl+tqq7W1NavrLC1tLWvqrHOzc6toLCTfZiCZYmnnKm9u7+/v7/7CJXkAAAAAXRSTlMAQObYZgAAAgxJREFUOMutk21X00AQhUulWKiRGreNszVGJGnWJgquNSndWohvlLaKNFRQUXmRqqgoyv8/ziZtT+HUb9wvOSfP3buTmUkicaGaSF6aTE1dTo+n6enUTCaTuaIoyszVMXw2lYmkRMpeO8/V65KSXF7TtBtAC/TmWa7fQkwNTSpvGAZQenuUz91BDvOSSowyrdGM2SkZPz84jirazCJ3h/WXZHFRfM5xcpIXbRcIHRju3UeDi9hZ0HV18QHBANtlhA8iHpbjgEe65J7nV5C7jPNsv39L2B6C5yVGXqoK4kYGqEWGx5PYPtC0uq4uLa8g94MnfcPTyPDsObb3hbaqq2pDUdaavi9apslYm8PL2PAKewv5iqouNhRqkfWGaBHGGAF43U9AAzcqqufVqcVho9kJpWETWDdu8xs0UGMVy1shsBUK0dxGztH0NjK8q8v52cb7UnVh50MgxHT4Ud7Amfkp/kxdUXYpLzq+HwQR38PDbQs9tf6o9ncppWBvdYQQnWa4l8ULLGDmwWBWAjm1mFv43ArD7UNLnueMwXD35vaRWwTwXaEAsj6K3N0YjrvnlZET0sbmAW9vUvSa5s7I8n4JstLAUfKBIab79dvoSh2JcswBkErufD+7lJ3qOhliZrKDH+fXOnlUXyOxweTdn+N+nuTx8a/fJ92Twz9///NvJdLp3ulpb6KWuFD9A1S5YIsyruDwAAAAAElFTkSuQmCC";
        helium = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAhFBMVEX///80UNE1UdM1UdQzUNEyTtE8V9NTa9i4wvBKY9bS2fb+/v9NZtfl6fpBW9TU2vaJmuVedNs4VNLByvKDlOPi5/l8juKst+2bqen7/P/z9f2grepDXdQvTNCVpOeCk+NUbNhFX9XO1fX19/7b4Piptez2+P5xhN+1wO/q7fv5+v6Zp+jzh9eJAAAAAXRSTlMAQObYZgAAAQZJREFUOMuVk9kSgjAMRW01ol5bURStK4q7//9/hpEZAxTQPLW5p02ztNP5yZTXhK591lU+vUdio6o69fsVQnXF+WAwCMqEuICGI2A0pHpgbAAz9gKk2E2Wb5jYbEVUAoJwyr5ZBEQz1qdhUABobrCI+dwSWHKm8QJmThJYwWG92e72wH633ax5uyoAB7C5KImdi5PIsY5DATiGp5SR8+WaXs68SE/hUQIc3d7uD+DJBjzuN/tJQ9SBHcnLwDmYV6LzLP8A2kKIR169j8zSdI1pthYqL7XOSk2eUn+apeublfeX7KS23U0D853JmpETQ6uzoa18DUn4xr70MTx6KYpHb/+8TfYGWZIa2Yf8cLUAAAAASUVORK5CYII=";
      };
      mkApplication = name: target: icon: {
        errors = false;
        quotes = false;
        closeme = false;
        changestate = "";
        inherit icon name;
        path = "${pkgs.xdg-utils}/bin/xdg-open";
        args = "x-external-application://${target}/[HREF]";
        pre = "";
        post = "";
        toolbar = true;
        context = [
          "page"
          "link"
          "image"
          "video"
          "audio"
        ];
        pattern = "";
        filters = "";
        redirects = "";
        index = "";
      };
      preferences = pkgs.writeText "external-application-button-preferences.json" (
        builtins.toJSON {
          active = "open-in-zen";
          save = "open-in-zen";
          apps = {
            "open-in-zen" = mkApplication "Open in Zen" "zen" icons.zen;
            "open-in-floorp" = mkApplication "Open in Floorp" "floorp" icons.floorp;
            "open-in-media-downloader" =
              mkApplication "Open in Media Downloader" "media-downloader"
                icons.mediaDownloader;
            "open-in-mpv" = mkApplication "Open in MPV" "mpv" icons.mpv;
            "open-in-helium" = mkApplication "Open in Helium" "helium" icons.helium;
          };
          faqs = false;
          exaccess = false;
          "mcp-server" = false;
          "mcp-log" = false;
          "mcp-extensions" = [ ];
        }
      );
    in
    {
      xdg.dataFile."applications/external-application.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=External Application Launcher
        Exec=${externalApplication}/bin/external-application %u
        StartupNotify=false
        MimeType=x-scheme-handler/x-external-application;
        Terminal=false
      '';

      xdg.mimeApps.defaultApplications."x-scheme-handler/x-external-application" = [
        "external-application.desktop"
      ];

      services.flatpak.overrides = {
        "app.zen_browser.zen".Context.persistent = [ ".mozilla" ];
        "one.ablaze.floorp".Context.persistent = [ ".mozilla" ];
      };

      home = {
        activation = {
          externalApplicationDesktopDatabase = config.lib.dag.entryAfter [ "writeBoundary" ] ''
            ${pkgs.desktop-file-utils}/bin/update-desktop-database "${config.xdg.dataHome}/applications"
          '';

          externalApplicationPreferences = config.lib.dag.entryAfter [ "writeBoundary" ] ''
            destination="${config.xdg.dataHome}/external-application-button-preferences.json"
            ${pkgs.coreutils}/bin/rm -f "$destination"
            ${pkgs.coreutils}/bin/install -D -m 0644 ${preferences} "$destination"
          '';

          externalApplicationNativeMessaging = config.lib.dag.entryAfter [ "writeBoundary" ] ''
            for app_id in app.zen_browser.zen one.ablaze.floorp; do
              directory="$HOME/.var/app/$app_id/.mozilla/native-messaging-hosts"
              ${pkgs.coreutils}/bin/install -D -m 0755 ${nativeHost} "$directory/com.add0n.node"
              ${pkgs.coreutils}/bin/install -m 0644 ${nativeHostManifest} "$directory/com.add0n.node.json"
            done
          '';
        };
      };
    };
}
