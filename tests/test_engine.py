import functools
import hashlib
import http.server
import io
import json
import pathlib
import sys
import tempfile
import threading
import types
import unittest
import zipfile
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Python/app"))
bridge = types.ModuleType("_ios_bridge")
bridge.emit = lambda event: None
bridge.is_cancelled = lambda: False
bridge.evaluate_js = lambda script: '{"type":"error","error":"fixture"}'
sys.modules["_ios_bridge"] = bridge

from downloader import (install_latest_engine, parse_custom_arguments, run,
                        select_streams, select_subtitle, validate_url)


def video(height, *, audio=False, codec="avc1.640028", drm=False, ext="mp4", protocol="https"):
    return {"format_id": str(height), "height": height, "ext": ext, "vcodec": codec,
            "acodec": "mp4a.40.2" if audio else "none", "protocol": protocol, "has_drm": drm}


def audio(*, ext="m4a", codec="mp4a.40.2"):
    return {"format_id": "140", "ext": ext, "vcodec": "none", "acodec": codec,
            "protocol": "https", "abr": 128}


class FormatSelectionTests(unittest.TestCase):
    def test_ceiling_selects_separate_video_and_audio(self):
        info = {"formats": [video(2160), video(1080), video(720, audio=True), audio()]}
        chosen, sound = select_streams(info, "MP4", 1080)
        self.assertEqual(chosen["height"], 1080)
        self.assertEqual(sound["format_id"], "140")

    def test_best_filters_incompatible_and_drm(self):
        info = {"formats": [video(2160, codec="av01.0.01M.08"), video(1080, drm=True),
                            video(720, audio=True)]}
        chosen, sound = select_streams(info, "MP4", 0)
        self.assertEqual(chosen["height"], 720)
        self.assertIsNone(sound)

    def test_missing_separate_audio_uses_complete_video(self):
        chosen, sound = select_streams({"formats": [video(1080), video(720, audio=True)]}, "MP4", 0)
        self.assertEqual(chosen["height"], 720)
        self.assertIsNone(sound)

    def test_missing_audio_is_reported(self):
        with self.assertRaises(ValueError):
            select_streams({"formats": [video(1080)]}, "MP4", 0)

    def test_m4a_selects_audio_without_video(self):
        chosen, sound = select_streams({"formats": [video(1080), audio()]}, "M4A", 0)
        self.assertIsNone(chosen)
        self.assertEqual(sound["ext"], "m4a")

    def test_extension_preference_selects_requested_container(self):
        webm = video(720, audio=True, codec="vp9", ext="webm")
        chosen, chosen_audio = select_streams(
            {"formats": [video(1080, audio=True), webm]}, "MP4", 1080, "webm", "")
        self.assertEqual(chosen["ext"], "webm")
        self.assertIsNone(chosen_audio)

    def test_invalid_or_missing_extension_is_reported(self):
        with self.assertRaisesRegex(ValueError, "확장자"):
            select_streams({"formats": [video(720, audio=True)]}, "MP4", 0, "../mp4", "")
        with self.assertRaisesRegex(ValueError, "\\.webm"):
            select_streams({"formats": [video(720, audio=True)]}, "MP4", 0, "webm", "")

    def test_missing_h264_falls_back_to_complete_original(self):
        reels = video(1080, audio=True, codec="hvc1.1.6.L120", ext="mp4", protocol="m3u8_native")
        chosen, sound = select_streams({"formats": [reels]}, "MP4", 1080)
        self.assertIs(chosen, reels)
        self.assertIsNone(sound)

    def test_original_format_prefers_complete_stream_and_keeps_extension(self):
        webm = video(1080, audio=True, codec="vp9", ext="webm")
        split = video(2160, audio=False, codec="vp9", ext="webm")
        chosen, sound = select_streams({"formats": [webm, split, audio()]}, "MP4", 0, "", "", True)
        self.assertEqual(chosen["height"], 1080)
        self.assertEqual(chosen["ext"], "webm")
        self.assertIsNone(sound)

    def test_audio_falls_back_to_original_container(self):
        opus = audio(ext="webm", codec="opus")
        _, sound = select_streams({"formats": [opus]}, "M4A", 0)
        self.assertEqual(sound["ext"], "webm")

    def test_custom_argument_allowlist(self):
        options = parse_custom_arguments(
            '--socket-timeout 25 --retries=4 --fragment-retries infinite '
            '--user-agent "Test Agent" --add-header "X-Test: yes"')
        self.assertEqual(options["socket_timeout"], 25)
        self.assertEqual(options["retries"], 4)
        self.assertEqual(options["fragment_retries"], float("inf"))
        self.assertEqual(options["http_headers"], {"User-Agent": "Test Agent", "X-Test": "yes"})
        for unsafe in ("--exec whoami", "--paths /tmp", "https://example.com", "--plugin-dirs x"):
            with self.subTest(unsafe=unsafe), self.assertRaises(ValueError):
                parse_custom_arguments(unsafe)

    def test_subtitle_prefers_manual_then_requested_language(self):
        info = {
            "subtitles": {"en-US": [{"ext": "vtt", "url": "https://example.com/manual"}]},
            "automatic_captions": {"ko": [{"ext": "vtt", "url": "https://example.com/auto"}]},
        }
        language, item, automatic = select_subtitle(info, "ko,en", True)
        self.assertEqual(language, "ko")
        self.assertTrue(automatic)
        self.assertIn("auto", item["url"])
        language, _, automatic = select_subtitle(info, "en", True)
        self.assertEqual(language, "en-US")
        self.assertFalse(automatic)

    def test_rejects_file_and_credentials(self):
        for value in ("file:///etc/passwd", "https://name:secret@example.com/video", "not a url"):
            with self.assertRaises(ValueError): validate_url(value)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class MemoryResponse(io.BytesIO):
    def __init__(self, value):
        super().__init__(value)
        self.headers = {"Content-Length": str(len(value))}

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class EngineUpdaterTests(unittest.TestCase):
    def test_installs_verified_wheel_and_writes_current_marker(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as wheel:
            wheel.writestr("yt_dlp/__init__.py", "# fixture")
            wheel.writestr("yt_dlp/version.py", "__version__ = '2099.01.01'")
        wheel_data = archive.getvalue()
        metadata = json.dumps({
            "info": {"version": "2099.01.01"},
            "urls": [{"packagetype": "bdist_wheel", "filename": "yt_dlp-2099.01.01-py3-none-any.whl",
                      "url": "https://example.com/package.whl",
                      "digests": {"sha256": hashlib.sha256(wheel_data).hexdigest()}}],
        }).encode()
        responses = iter((MemoryResponse(metadata), MemoryResponse(wheel_data)))
        with tempfile.TemporaryDirectory() as root, patch("downloader.urlopen", side_effect=lambda *a, **k: next(responses)):
            version, changed = install_latest_engine(root, lambda *a, **k: None)
            self.assertEqual(version, "2099.01.01")
            self.assertTrue(changed)
            self.assertEqual((pathlib.Path(root) / "current").read_text(), version)
            self.assertTrue((pathlib.Path(root) / version / "yt_dlp/__init__.py").is_file())


class ActualDownloaderTests(unittest.TestCase):
    def test_real_http_download_of_two_streams_without_external_process(self):
        from yt_dlp import YoutubeDL
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "source-video.mp4").write_bytes(b"fixture-video" * 8192)
            (root / "source-audio.m4a").write_bytes(b"fixture-audio" * 2048)
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=folder))
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                base = f"http://127.0.0.1:{server.server_port}"
                vf, af = video(1080), audio()
                for fmt, path in ((vf, "source-video.mp4"), (af, "source-audio.m4a")):
                    fmt["protocol"] = "http"; fmt["url"] = f"{base}/{path}"
                info = {"id": "fixture", "title": "Local fixture", "extractor": "fixture",
                        "extractor_key": "Fixture", "webpage_url": base, "formats": [vf, af]}
                request = json.dumps({"operation": "download", "url": base,
                                      "format": "MP4", "quality": 1080, "directory": str(root / "output")})
                events = []
                with patch.object(YoutubeDL, "extract_info", return_value=info), \
                     patch.object(bridge, "emit", side_effect=lambda raw: events.append(json.loads(raw))), \
                     patch("subprocess.Popen", side_effect=AssertionError("An external process was attempted")):
                    result = json.loads(run(request))
                self.assertTrue(result["ok"], result)
                self.assertEqual(pathlib.Path(result["video"]).read_bytes(), (root / "source-video.mp4").read_bytes())
                self.assertEqual(pathlib.Path(result["audio"]).read_bytes(), (root / "source-audio.m4a").read_bytes())
                values = [event["progress"] for event in events if event.get("progress") is not None]
                self.assertTrue(values)
                self.assertEqual(values[-1], 1.0)
                self.assertEqual(values, sorted(values))
                self.assertTrue(any(event.get("phase") == "metadata" for event in events))
                self.assertTrue(any("다운로드 시작" in event.get("message", "") for event in events))
                self.assertTrue(any("다운로드 완료" in event.get("message", "") for event in events))
            finally:
                server.shutdown(); server.server_close(); thread.join()

    def test_cancel_before_network(self):
        with patch.object(bridge, "is_cancelled", return_value=True):
            result = json.loads(run(json.dumps({"url": "https://example.com/video", "operation": "inspect"})))
        self.assertTrue(result["cancelled"])

    def test_logger_redacts_signed_urls_and_emits_warning(self):
        from yt_dlp import YoutubeDL
        events = []
        options = {}
        def extract(ydl, url, download=False):
            options.update(ydl.params)
            ydl.params["logger"].warning("테스트 안내 https://example.com/video?token=secret")
            return {"id": "fixture", "title": "내 영상"}
        with patch.object(YoutubeDL, "extract_info", autospec=True, side_effect=extract), \
             patch.object(bridge, "emit", side_effect=lambda raw: events.append(json.loads(raw))):
            result = json.loads(run(json.dumps({"url": "https://example.com/one", "operation": "inspect"})))
        self.assertTrue(result["ok"], result)
        warning = next(event for event in events if event.get("level") == "warning")
        self.assertIn("[링크]", warning["message"])
        self.assertNotIn("secret", json.dumps(events))
        self.assertEqual(options["format"], "best")

    def test_javascriptcore_provider_registers_and_loads_bundled_solver(self):
        from yt_dlp import YoutubeDL
        from yt_dlp.extractor.youtube import YoutubeIE
        from yt_dlp.extractor.youtube.jsc._builtin.ejs import ScriptType
        from ios_jsc import AppleJavaScriptCoreJCP
        with YoutubeDL({"quiet": True, "js_runtimes": {}}) as ydl:
            ie = YoutubeIE(ydl)
            ie.initialize()
            provider = next(p for p in ie._jsc_director.providers.values() if isinstance(p, AppleJavaScriptCoreJCP))
            self.assertTrue(provider.is_available())
            self.assertGreater(len(provider._get_script(ScriptType.LIB).code), 1000)
            self.assertGreater(len(provider._get_script(ScriptType.CORE).code), 1000)


if __name__ == "__main__":
    unittest.main()
