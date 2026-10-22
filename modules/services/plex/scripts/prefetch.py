import argparse
import hashlib
import hmac
import http.client
import json
import logging
import os
import re
import signal
import stat
import threading
import time
import xml.etree.ElementTree as ET
from collections import OrderedDict
from dataclasses import dataclass
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path, PurePosixPath
from xml.parsers import expat

MIB = 1024 * 1024
MAX_BODY = 2 * MIB
PLAY_EVENTS = {"media.play", "media.resume", "media.scrobble", "playback.started"}
STOP_EVENTS = {"media.pause", "media.stop"}
LOG = logging.getLogger("plex-prefetch")


class InvalidEvent(ValueError):
    pass


def rating_key(value):
    value = str(value)
    if not re.fullmatch(r"[1-9][0-9]{0,19}", value):
        raise InvalidEvent("Invalid metadata key")
    return value


@dataclass(frozen=True)
class Event:
    kind: str
    player: str
    source: str


def parse_event(content_type, body, server_id):
    if len(body) > MAX_BODY or len(content_type) > 512:
        raise InvalidEvent("Payload too large")
    message = BytesParser(policy=policy.default).parsebytes(
        b"Content-Type: " + content_type.encode("ascii") + b"\r\n\r\n" + body
    )
    if message.get_content_type() != "multipart/form-data" or not message.is_multipart():
        raise InvalidEvent("Expected multipart form")
    parts = list(message.iter_parts())
    payloads = [part for part in parts if part.get_param("name", header="content-disposition") == "payload"]
    if len(parts) > 4 or len(payloads) != 1 or payloads[0].is_multipart():
        raise InvalidEvent("Expected one payload")
    encoded = payloads[0].get_payload(decode=True)
    if not isinstance(encoded, (str, bytes)):
        raise InvalidEvent("Expected JSON payload")
    payload = json.loads(encoded)
    if not isinstance(payload, dict):
        raise InvalidEvent("Expected event object")
    kind = payload.get("event")
    if kind not in PLAY_EVENTS | STOP_EVENTS:
        return None
    if payload.get("Server", {}).get("uuid") != server_id:
        raise InvalidEvent("Wrong server")
    metadata = payload.get("Metadata", {})
    if metadata.get("type") != "episode":
        return None
    player = payload.get("Player", {}).get("uuid")
    if not isinstance(player, str) or not 1 <= len(player) <= 256:
        raise InvalidEvent("Missing player")
    return Event(kind, player, rating_key(metadata.get("ratingKey")))


def parse_xml(body):
    if len(body) > 8 * MIB:
        raise ValueError("Plex response too large")
    tree = ET.TreeBuilder()
    parser = expat.ParserCreate()
    parser.StartElementHandler = tree.start
    parser.EndElementHandler = tree.end
    parser.CharacterDataHandler = tree.data

    def reject_declaration(*args):
        raise ValueError("XML declarations are forbidden")

    parser.StartDoctypeDeclHandler = reject_declaration
    parser.EntityDeclHandler = reject_declaration
    parser.ExternalEntityRefHandler = reject_declaration
    parser.Parse(body, True)
    return tree.close()


class Plex:
    def __init__(self, port, token):
        self.port = port
        self.token = token
        self.server_id = self.xml("/identity").attrib["machineIdentifier"]

    def xml(self, path):
        if not re.fullmatch(r"/(identity|status/sessions|library/metadata/[1-9][0-9]{0,19}(/allLeaves)?)", path):
            raise ValueError("Unsupported Plex API path")
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        try:
            connection.request("GET", path, headers={"X-Plex-Token": self.token, "Accept": "application/xml"})
            response = connection.getresponse()
            if response.status != 200:
                raise ValueError("Plex API request rejected")
            return parse_xml(response.read(8 * MIB + 1))
        finally:
            connection.close()

    def playing(self, player, source):
        for video in self.xml("/status/sessions").findall("Video"):
            client = video.find("Player")
            if (
                video.get("type") == "episode"
                and video.get("ratingKey") == source
                and client is not None
                and client.get("machineIdentifier") == player
                and client.get("state") == "playing"
            ):
                return video
        return None

    def next_episode(self, event):
        current = self.playing(event.player, event.source)
        if current is None:
            return None
        season, episode = int(current.attrib["parentIndex"]), int(current.attrib["index"])
        if season == 0:
            return None
        show = rating_key(current.attrib["grandparentRatingKey"])
        episodes = self.xml(f"/library/metadata/{show}/allLeaves").findall("Video")
        candidates = [
            item for item in episodes
            if item.get("type") == "episode"
            and int(item.get("parentIndex", "0")) > 0
            and (int(item.attrib["parentIndex"]), int(item.attrib["index"])) > (season, episode)
        ]
        if not candidates:
            return None
        following = min(candidates, key=lambda item: (int(item.attrib["parentIndex"]), int(item.attrib["index"])))
        target = rating_key(following.attrib["ratingKey"])
        details = self.xml(f"/library/metadata/{target}").find("Video")
        if details is None or details.get("type") != "episode":
            return None
        media = details.findall("Media")
        active_media = current.find("Media")
        if active_media is not None:
            resolution = active_media.get("videoResolution")
            media.sort(key=lambda item: item.get("videoResolution") != resolution)
        for version in media:
            part = version.find("Part")
            if part is not None and part.get("file"):
                return Job(event.player, event.source, target, part.attrib["file"])
        return None


@dataclass(frozen=True)
class Job:
    player: str
    source: str
    target: str
    path: str

    @property
    def key(self):
        return self.target, self.path


def open_media(path, roots):
    candidate = PurePosixPath(path)
    if not candidate.is_absolute() or ".." in candidate.parts:
        raise PermissionError("Outside media roots")
    for root in roots:
        try:
            relative = candidate.relative_to(root)
        except ValueError:
            continue
        if not relative.parts:
            raise PermissionError("Expected media file")
        directory = os.open(root, os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            for component in relative.parts[:-1]:
                child = os.open(component, os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=directory)
                os.close(directory)
                directory = child
            descriptor = os.open(
                relative.parts[-1], os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC,
                dir_fd=directory,
            )
        finally:
            os.close(directory)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise PermissionError("Expected regular media file")
        except OSError:
            os.close(descriptor)
            raise
        return descriptor
    raise PermissionError("Outside media roots")


def read_prefix(path, roots, limit, rate, cancelled):
    if not 0 < limit <= 256 * MIB or not 0 < rate <= 10 * MIB:
        raise ValueError("Prefetch budget exceeded")
    if cancelled.is_set():
        return 0, False
    descriptor = open_media(path, roots)
    total = 0
    try:
        # Keep this descriptor's speculative read-ahead within the bounded job.
        os.posix_fadvise(descriptor, 0, limit, os.POSIX_FADV_RANDOM)
        size = min(limit, os.fstat(descriptor).st_size)
        while total < size and not cancelled.is_set():
            data = os.read(descriptor, min(MIB, size - total))
            if not data:
                break
            total += len(data)
            if cancelled.wait(len(data) / rate):
                break
        return total, total == size and not cancelled.is_set()
    finally:
        os.close(descriptor)


class Prefetcher:
    def __init__(self, plex, roots, limit, rate, reader=read_prefix, clock=time.monotonic):
        self.plex, self.roots, self.limit, self.rate = plex, roots, limit, rate
        self.reader, self.clock = reader, clock
        self.condition = threading.Condition()
        self.wanted = OrderedDict()
        self.finished = OrderedDict()
        self.current = None
        self.cancelled = threading.Event()
        self.stopping = False
        self.worker = threading.Thread(target=self.run, daemon=True)

    def start(self):
        self.worker.start()

    def handle(self, event):
        if event.kind in STOP_EVENTS:
            with self.condition:
                existing = self.wanted.get(event.player)
                if existing is not None and existing.source == event.source:
                    del self.wanted[event.player]
                    self.cancel_unwanted()
            return
        job = self.plex.next_episode(event)
        if job is None:
            return
        with self.condition:
            now = self.clock()
            self.finished = OrderedDict((key, stamp) for key, stamp in self.finished.items() if now - stamp < 300)
            self.wanted.pop(job.player, None)
            if job.key in self.finished or len(self.wanted) >= 16:
                self.cancel_unwanted()
                return
            self.wanted[job.player] = job
            self.cancel_unwanted()
            self.condition.notify_all()

    def cancel_unwanted(self):
        if self.current is not None and not any(job.key == self.current.key for job in self.wanted.values()):
            self.cancelled.set()

    def close(self):
        with self.condition:
            self.stopping = True
            self.cancelled.set()
            self.condition.notify_all()
        if self.worker.is_alive():
            self.worker.join(timeout=2)

    def run(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.stopping or any(job.key not in self.finished for job in self.wanted.values()))
                if self.stopping:
                    return
                job = next(job for job in self.wanted.values() if job.key not in self.finished)
                observers = dict(self.wanted)
                self.current = job
                self.cancelled = threading.Event()
            complete = False
            try:
                # Recheck queued work against Plex instead of trusting an old callback.
                watchers = [item for item in observers.values() if item.key == job.key]
                if any(self.plex.playing(item.player, item.source) is not None for item in watchers):
                    started = self.clock()
                    total, complete = self.reader(job.path, self.roots, self.limit, self.rate, self.cancelled)
                    LOG.info("Next-episode prefix: bytes=%d seconds=%.3f complete=%s", total, self.clock() - started, complete)
            except Exception as error:
                LOG.warning("Prefetch failed (%s)", type(error).__name__)
            finally:
                with self.condition:
                    if complete:
                        self.finished[job.key] = self.clock()
                        while len(self.finished) > 128:
                            self.finished.popitem(last=False)
                    # A newer resume event survives a cancelled read, without automatic retries.
                    self.wanted = OrderedDict(
                        (player, item) for player, item in self.wanted.items()
                        if item.key != job.key or (not complete and observers.get(player) is not item)
                    )
                    self.current = None
                    self.condition.notify_all()


def handler_for(prefetcher, secret_path, server_id):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def setup(self):
            super().setup()
            self.connection.settimeout(3)

        def reply(self, status):
            self.send_response(status)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_GET(self):
            self.reply(200 if self.path == "/health" else 404)

        def do_POST(self):
            if not hmac.compare_digest(self.path.encode("utf-8"), secret_path.encode("ascii")):
                self.reply(403)
                return
            lengths = self.headers.get_all("Content-Length", [])
            if self.headers.get("Transfer-Encoding") or len(lengths) != 1 or not re.fullmatch(r"[0-9]{1,8}", lengths[0]):
                self.reply(400)
                return
            length = int(lengths[0])
            if not 0 < length <= MAX_BODY:
                self.reply(413)
                return
            try:
                body = self.rfile.read(length)
                if len(body) != length:
                    raise InvalidEvent("Truncated body")
                event = parse_event(self.headers.get("Content-Type", ""), body, server_id)
            except (ValueError, TypeError, AttributeError, UnicodeError, OSError, RecursionError):
                self.reply(400)
                return
            try:
                if event is not None:
                    prefetcher.handle(event)
            except Exception as error:
                LOG.warning("Playback lookup failed (%s)", type(error).__name__)
                self.reply(503)
                return
            self.reply(202)

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    arguments = parser.parse_args()
    config = json.loads(arguments.config.read_text())
    logging.basicConfig(level=logging.INFO, format="%(name)s: %(message)s")
    credential = Path(os.environ["CREDENTIALS_DIRECTORY"]) / "plex-preferences"
    token = parse_xml(credential.read_bytes()).get("PlexOnlineToken")
    if not token:
        raise ValueError("Plex has no owner token; claim the server first")
    plex = Plex(config["plexPort"], token)
    secret = hmac.new(token.encode(), ("plex-prefetch:" + plex.server_id).encode(), hashlib.sha256).hexdigest()
    secret_path = "/prefetch/" + secret
    runtime = Path(os.environ["RUNTIME_DIRECTORY"])
    url_file = runtime / "webhook-url"
    descriptor = os.open(url_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write(f"http://127.0.0.1:{config['port']}{secret_path}\n")
    prefetcher = Prefetcher(plex, config["roots"], config["prefixMiB"] * MIB, config["rateMiB"] * MIB)
    stopped = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: stopped.set())
    with HTTPServer(("127.0.0.1", config["port"]), handler_for(prefetcher, secret_path, plex.server_id)) as server:
        server.timeout = 0.5
        prefetcher.start()
        LOG.info("Ready; private webhook URL is in /run/plex-prefetch/webhook-url")
        try:
            while not stopped.is_set():
                server.handle_request()
        finally:
            prefetcher.close()


if __name__ == "__main__":
    main()
