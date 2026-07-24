#!/usr/bin/env python3

import json
import struct
import subprocess
import sys
from urllib.parse import urlparse

MAX_MESSAGE_SIZE = 65_536
XDG_OPEN = "/usr/bin/xdg-open"


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


def valid_url(url):
    if not isinstance(url, str) or any(
        char.isspace() or ord(char) < 32 or char == "\\" for char in url
    ):
        return False

    prefix = "x-url2app://"
    if not url.startswith(prefix):
        return False

    target = url.removeprefix(prefix)
    parsed = urlparse(target)
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
        "cmd",
        "command",
        "arguments",
        "stdin",
        "properties",
    }:
        return {"code": 126, "stdout": "", "stderr": "request denied"}

    url = request.get("arguments")
    if (
        request.get("cmd") != "exec"
        or request.get("command") != XDG_OPEN
        or not isinstance(url, list)
        or len(url) != 1
        or request.get("stdin") != []
        or request.get("properties") != {}
        or not valid_url(url[0])
    ):
        return {"code": 126, "stdout": "", "stderr": "request denied"}

    try:
        completed = subprocess.run(
            [XDG_OPEN, url[0]],
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


def main():
    try:
        request = read_message()
    except (UnicodeDecodeError, ValueError, json.JSONDecodeError):
        return 64

    write_message(response_for(request))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
