import http.client
import importlib.util
import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import Mock, patch

specification = importlib.util.spec_from_file_location("prefetch", Path(__file__).resolve().parents[1] / "scripts/prefetch.py")
if specification is None or specification.loader is None:
    raise RuntimeError("Cannot load prefetch implementation")
prefetch = importlib.util.module_from_spec(specification)
sys.modules[specification.name] = prefetch
specification.loader.exec_module(prefetch)


def multipart(payload, poster=False):
    body = b'--fixture\r\nContent-Disposition: form-data; name="payload"\r\n\r\n'
    body += json.dumps(payload).encode() + b"\r\n"
    if poster:
        body += b'--fixture\r\nContent-Disposition: form-data; name="thumb"; filename="thumb.jpg"\r\n\r\nposter\r\n'
    return "multipart/form-data; boundary=fixture", body + b"--fixture--\r\n"


def payload(kind="media.play", player="player", source: str | None = "11"):
    return {"event": kind, "Server": {"uuid": "server"}, "Player": {"uuid": player},
            "Metadata": {"type": "episode", "ratingKey": source, "file": "/untrusted/body/path"}}


def xml(videos):
    return prefetch.parse_xml(("<MediaContainer>" + videos + "</MediaContainer>").encode())


class FixturePlex(prefetch.Plex):
    def __init__(self):
        self.responses = {
            "/status/sessions": xml('<Video type="episode" ratingKey="11" grandparentRatingKey="10" parentIndex="1" index="1"><Player machineIdentifier="player" state="playing"/><Media videoResolution="1080"/></Video>'),
            "/library/metadata/10/allLeaves": xml('<Video type="episode" ratingKey="13" parentIndex="1" index="3"/><Video type="episode" ratingKey="12" parentIndex="1" index="2"/><Video type="episode" ratingKey="99" parentIndex="0" index="2"/>'),
            "/library/metadata/12": xml('<Video type="episode"><Media videoResolution="4k"><Part file="/mnt/nas/video/4k.mkv"/></Media><Media videoResolution="1080"><Part file="/mnt/nas/video/æøå.mkv"/></Media></Video>'),
        }
        self.calls = []

    def xml(self, path):
        self.calls.append(path)
        return self.responses[path]


class ParsingTests(unittest.TestCase):
    def test_native_events_with_and_without_poster(self):
        for kind in prefetch.PLAY_EVENTS | prefetch.STOP_EVENTS:
            for poster in (False, True):
                with self.subTest(kind=kind, poster=poster):
                    self.assertEqual(prefetch.parse_event(*multipart(payload(kind), poster), "server"),
                                     prefetch.Event(kind, "player", "11"))

    def test_wrong_server_and_injected_metadata_keys_are_rejected(self):
        with self.assertRaises(prefetch.InvalidEvent):
            prefetch.parse_event(*multipart(payload()), "another-server")
        for source in ("../secrets", "1?token=bad", "0", None):
            with self.subTest(source=source), self.assertRaises(prefetch.InvalidEvent):
                prefetch.parse_event(*multipart(payload(source=source)), "server")

    def test_movies_and_unrelated_notifications_do_not_schedule_reads(self):
        movie = payload()
        movie["Metadata"]["type"] = "movie"
        self.assertIsNone(prefetch.parse_event(*multipart(movie), "server"))
        self.assertIsNone(prefetch.parse_event(*multipart(payload("library.new")), "server"))

    def test_xml_entity_declarations_are_rejected_in_both_encodings(self):
        document = '<!DOCTYPE x [<!ENTITY secret SYSTEM "file:///etc/passwd">]><x>&secret;</x>'
        for encoding in ("utf-8", "utf-16"):
            with self.subTest(encoding=encoding), self.assertRaises(ValueError):
                prefetch.parse_xml(document.encode(encoding))

    def test_xml_size_is_bounded(self):
        with self.assertRaises(ValueError):
            prefetch.parse_xml(b"x" * (8 * prefetch.MIB + 1))


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.plex = FixturePlex()
        self.event = prefetch.Event("media.play", "player", "11")

    def test_chronological_successor_matching_current_resolution(self):
        self.assertEqual(self.plex.next_episode(self.event),
                         prefetch.Job("player", "11", "12", "/mnt/nas/video/æøå.mkv"))

    def test_successor_crosses_seasons_but_skips_specials(self):
        self.plex.responses["/library/metadata/10/allLeaves"] = xml(
            '<Video type="episode" ratingKey="12" parentIndex="2" index="1"/>'
            '<Video type="episode" ratingKey="99" parentIndex="0" index="20"/>')
        self.assertEqual(self.plex.next_episode(self.event).target, "12")

    def test_stale_forged_and_paused_sessions_do_not_lookup_library(self):
        for state, player, source in (("paused", "player", "11"), ("playing", "other", "11"), ("playing", "player", "98")):
            self.plex.responses["/status/sessions"].find("Video/Player").set("state", state)
            self.plex.calls.clear()
            self.assertIsNone(self.plex.next_episode(prefetch.Event("media.play", player, source)))
            self.assertEqual(self.plex.calls, ["/status/sessions"])

    def test_final_episode_does_not_prefetch_another_show(self):
        self.plex.responses["/library/metadata/10/allLeaves"] = xml("")
        self.assertIsNone(self.plex.next_episode(self.event))


class InstantCancellation:
    def __init__(self, cancel_after=None):
        self.waits = []
        self.cancel_after = cancel_after

    def is_set(self):
        return self.cancel_after is not None and len(self.waits) >= self.cancel_after

    def wait(self, duration):
        self.waits.append(duration)
        return self.is_set()


class ReadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "video"
        self.root.mkdir()
        self.media = self.root / "episode.mkv"
        self.media.write_bytes(b"x" * (3 * prefetch.MIB))

    def test_read_is_bounded_rate_limited_and_does_not_modify_media(self):
        before = self.media.stat()
        cancellation = InstantCancellation()
        total, complete = prefetch.read_prefix(str(self.media), [str(self.root)], 2 * prefetch.MIB,
                                               10 * prefetch.MIB, cancellation)
        self.assertEqual((total, complete), (2 * prefetch.MIB, True))
        self.assertEqual(cancellation.waits, [0.1, 0.1])
        self.assertEqual(self.media.read_bytes(), b"x" * (3 * prefetch.MIB))
        self.assertEqual(self.media.stat().st_mtime_ns, before.st_mtime_ns)

    def test_pause_interrupts_before_the_next_chunk(self):
        cancellation = InstantCancellation(cancel_after=1)
        self.assertEqual(prefetch.read_prefix(str(self.media), [str(self.root)], 3 * prefetch.MIB,
                                              10 * prefetch.MIB, cancellation), (prefetch.MIB, False))

    def test_outside_paths_traversal_symlinks_and_special_files_are_rejected(self):
        outside = Path(self.temporary.name) / "private"
        outside.write_bytes(b"private")
        (self.root / "link").symlink_to(outside)
        (self.root / "directory-link").symlink_to(outside.parent, target_is_directory=True)
        os.mkfifo(self.root / "fifo")
        for path in (outside, str(self.root) + "/../private", self.root / "link",
                     self.root / "directory-link/private", self.root / "fifo", self.root):
            with self.subTest(path=path), self.assertRaises((PermissionError, OSError)):
                prefetch.open_media(str(path), [str(self.root)])

    def test_budget_cannot_exceed_the_approved_limits(self):
        for limit, rate in ((257 * prefetch.MIB, prefetch.MIB), (prefetch.MIB, 11 * prefetch.MIB)):
            with self.assertRaises(ValueError):
                prefetch.read_prefix(str(self.media), [str(self.root)], limit, rate, InstantCancellation())


    def test_failed_read_setup_closes_the_file_descriptor(self):
        descriptor = os.open(self.media, os.O_RDONLY)
        with (
            patch.object(prefetch, "open_media", return_value=descriptor),
            patch.object(prefetch.os, "posix_fadvise", side_effect=OSError("fixture failure")),
            self.assertRaises(OSError),
        ):
            prefetch.read_prefix(str(self.media), [str(self.root)], prefetch.MIB,
                                 prefetch.MIB, InstantCancellation())
        with self.assertRaises(OSError):
            os.fstat(descriptor)


class WorkerTests(unittest.TestCase):
    def make_worker(self, reader, clock=lambda: 0):
        plex = Mock()
        plex.next_episode.side_effect = lambda event: prefetch.Job(event.player, event.source, "12", "/media/next.mkv")
        plex.playing.return_value = object()
        worker = prefetch.Prefetcher(plex, ["/media"], prefetch.MIB, prefetch.MIB, reader, clock)
        self.addCleanup(worker.close)
        return worker

    def idle(self, worker):
        with worker.condition:
            self.assertTrue(worker.condition.wait_for(lambda: worker.current is None and not worker.wanted, timeout=3))

    def test_duplicate_events_and_multiple_viewers_share_one_read(self):
        entered, release = threading.Event(), threading.Event()
        reads = []

        def reader(*args):
            reads.append(args[0])
            entered.set()
            self.assertTrue(release.wait(3))
            return prefetch.MIB, True

        worker = self.make_worker(reader)
        worker.handle(prefetch.Event("media.play", "a", "11"))
        worker.start()
        self.assertTrue(entered.wait(3))
        worker.handle(prefetch.Event("media.resume", "a", "11"))
        worker.handle(prefetch.Event("playback.started", "b", "11"))
        worker.handle(prefetch.Event("media.pause", "a", "11"))
        self.assertFalse(worker.cancelled.is_set())
        release.set()
        self.idle(worker)
        worker.handle(prefetch.Event("media.play", "b", "11"))
        self.assertEqual(reads, ["/media/next.mkv"])
        self.assertFalse(worker.wanted)

    def test_stop_cancels_and_immediate_resume_is_not_lost(self):
        entered, release = threading.Event(), threading.Event()
        reads = []

        def reader(*args):
            reads.append(args[0])
            if len(reads) == 1:
                entered.set()
                self.assertTrue(release.wait(3))
                return 1, not args[-1].is_set()
            return prefetch.MIB, True

        worker = self.make_worker(reader)
        worker.handle(prefetch.Event("media.play", "a", "11"))
        worker.start()
        self.assertTrue(entered.wait(3))
        worker.handle(prefetch.Event("media.stop", "a", "11"))
        self.assertTrue(worker.cancelled.is_set())
        worker.handle(prefetch.Event("media.resume", "a", "11"))
        release.set()
        self.idle(worker)
        self.assertEqual(len(reads), 2)

    def test_finished_prefix_can_be_refreshed_by_a_later_scrobble(self):
        now = [0]
        reader = Mock(return_value=(prefetch.MIB, True))
        worker = self.make_worker(reader, lambda: now[0])
        worker.start()
        worker.handle(prefetch.Event("media.play", "a", "11"))
        self.idle(worker)
        now[0] = 301
        worker.handle(prefetch.Event("media.scrobble", "a", "11"))
        self.idle(worker)
        self.assertEqual(reader.call_count, 2)

    def test_stale_queue_entries_and_read_failures_do_not_retry_forever(self):
        for stale in (True, False):
            reader = Mock(side_effect=PermissionError("private path"))
            worker = self.make_worker(reader)
            worker.plex.playing.return_value = None if stale else object()
            worker.handle(prefetch.Event("media.play", "a", "11"))
            worker.start()
            self.idle(worker)
            self.assertEqual(reader.call_count, 0 if stale else 1)

    def test_waiting_players_are_bounded(self):
        worker = self.make_worker(Mock())
        for number in range(40):
            worker.handle(prefetch.Event("media.play", str(number), "11"))
        self.assertEqual(len(worker.wanted), 16)


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.manager = Mock()
        self.server = HTTPServer(("127.0.0.1", 0), prefetch.handler_for(self.manager, "/prefetch/fixture-secret", "server"))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(3)

    def request(self, path, body, content_type="multipart/form-data; boundary=fixture", extra=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        try:
            connection.request("POST", path, body, {"Content-Type": content_type, **(extra or {})})
            response = connection.getresponse()
            response.read()
            return response.status
        finally:
            connection.close()

    def test_authenticated_native_callback_is_dispatched(self):
        content_type, body = multipart(payload(), poster=True)
        self.assertEqual(self.request("/prefetch/fixture-secret", body, content_type), 202)
        self.manager.handle.assert_called_once_with(prefetch.Event("media.play", "player", "11"))

    def test_unauthenticated_malformed_and_oversized_requests_do_not_dispatch(self):
        _, body = multipart(payload())
        for path, data, extra, status in (
            ("/prefetch/wrong", body, {}, 403),
            ("/prefetch/fixture-secret", b"bad multipart", {}, 400),
            ("/prefetch/fixture-secret", b"", {"Content-Length": str(prefetch.MAX_BODY + 1)}, 413),
            ("/prefetch/fixture-secret", b"", {"Transfer-Encoding": "chunked"}, 400),
        ):
            with self.subTest(status=status):
                self.assertEqual(self.request(path, data, extra=extra), status)
        self.manager.handle.assert_not_called()

    def test_forged_server_does_not_dispatch(self):
        event = payload()
        event["Server"]["uuid"] = "foreign"
        self.assertEqual(self.request("/prefetch/fixture-secret", multipart(event)[1]), 400)
        self.manager.handle.assert_not_called()


class ApiTransportTests(unittest.TestCase):
    def test_token_uses_a_header_and_redirects_are_not_followed(self):
        requests = []

        class Api(BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

            def do_GET(self):
                requests.append((self.path, self.headers.get("X-Plex-Token")))
                self.send_response(302)
                self.send_header("Location", "/would-leak-token")
                self.end_headers()

        with HTTPServer(("127.0.0.1", 0), Api) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with self.assertRaises(ValueError):
                    prefetch.Plex(server.server_port, "fixture-token")
            finally:
                server.shutdown()
                thread.join(3)
        self.assertEqual(requests, [("/identity", "fixture-token")])


class IntegrationTests(unittest.TestCase):
    def test_callback_reads_only_the_authoritative_next_episode(self):
        with tempfile.TemporaryDirectory() as temporary:
            media = Path(temporary) / "next.mkv"
            media.write_bytes(b"fixture media" * 1024)
            plex = FixturePlex()
            plex.responses["/library/metadata/12"].find("Video/Media/Part").set("file", str(media))
            plex.responses["/library/metadata/12"].find("Video/Media").set("videoResolution", "1080")
            reads = []

            def reader(*args):
                result = prefetch.read_prefix(*args)
                reads.append((args[0], result))
                return result

            manager = prefetch.Prefetcher(plex, [temporary], prefetch.MIB, 10 * prefetch.MIB, reader)
            manager.start()
            try:
                with HTTPServer(("127.0.0.1", 0), prefetch.handler_for(manager, "/secret", "server")) as server:
                    thread = threading.Thread(target=server.serve_forever, daemon=True)
                    thread.start()
                    try:
                        content_type, body = multipart(payload())
                        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
                        connection.request("POST", "/secret", body, {"Content-Type": content_type})
                        response = connection.getresponse()
                        response.read()
                        self.assertEqual(response.status, 202)
                        connection.close()
                        with manager.condition:
                            self.assertTrue(manager.condition.wait_for(
                                lambda: manager.current is None and not manager.wanted, timeout=3))
                        self.assertEqual(reads, [(str(media), (media.stat().st_size, True))])
                        self.assertIn(("12", str(media)), manager.finished)
                    finally:
                        server.shutdown()
                        thread.join(3)
            finally:
                manager.close()

    def test_startup_uses_private_credentials_without_logging_the_capability(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "plex-preferences").write_text('<Preferences PlexOnlineToken="fixture-owner-token"/>')
            configuration = root / "config.json"
            configuration.write_text(json.dumps({
                "port": 32403, "plexPort": 32400, "roots": [temporary],
                "prefixMiB": 256, "rateMiB": 10,
            }))
            with (
                patch.dict(os.environ, CREDENTIALS_DIRECTORY=temporary, RUNTIME_DIRECTORY=temporary),
                patch.object(sys, "argv", ["prefetch", str(configuration)]),
                patch.object(prefetch, "Plex") as api,
                patch.object(prefetch.logging, "basicConfig"),
                patch.object(prefetch, "Prefetcher"),
                patch.object(prefetch, "HTTPServer") as http,
                patch.object(prefetch.signal, "signal") as signals,
                self.assertLogs("plex-prefetch", level="INFO") as logs,
            ):
                api.return_value.server_id = "server"
                http.return_value.__enter__.return_value.handle_request.side_effect = lambda: signals.call_args.args[1]()
                prefetch.main()
                api.assert_called_once_with(32400, "fixture-owner-token")
            url = (root / "webhook-url").read_text()
            self.assertRegex(url, r"^http://127\.0\.0\.1:32403/prefetch/[0-9a-f]{64}\n$")
            self.assertEqual((root / "webhook-url").stat().st_mode & 0o777, 0o600)
            self.assertNotIn("fixture-owner-token", url)
            self.assertNotIn(url.strip(), "\n".join(logs.output))
            self.assertNotIn("fixture-owner-token", "\n".join(logs.output))


if __name__ == "__main__":
    unittest.main()
