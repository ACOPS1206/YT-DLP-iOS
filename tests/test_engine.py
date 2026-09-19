import functools
import http.server
import json
import pathlib
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Python/app"))
bridge = types.ModuleType("_ios_bridge")
bridge.emit = lambda event: None
bridge.is_cancelled = lambda: False
bridge.evaluate_js = lambda script: '{"type":"error","error":"fixture"}'
sys.modules["_ios_bridge"] = bridge

from downloader import select_streams, validate_url, run


def video(height, *, audio=False, codec="avc1.640028", drm=False):
    return {"format_id": str(height), "height": height, "ext": "mp4", "vcodec": codec,
            "acodec": "mp4a.40.2" if audio else "none", "protocol": "https", "has_drm": drm}


def audio():
    return {"format_id": "140", "ext": "m4a", "vcodec": "none", "acodec": "mp4a.40.2",
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

    def test_rejects_file_and_credentials(self):
        for value in ("file:///etc/passwd", "https://name:secret@example.com/video", "not a url"):
            with self.assertRaises(ValueError): validate_url(value)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


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
        def extract(ydl, url, download=False):
            ydl.params["logger"].warning("테스트 안내 https://example.com/video?token=secret")
            return {"id": "fixture", "title": "내 영상"}
        with patch.object(YoutubeDL, "extract_info", autospec=True, side_effect=extract), \
             patch.object(bridge, "emit", side_effect=lambda raw: events.append(json.loads(raw))):
            result = json.loads(run(json.dumps({"url": "https://example.com/one", "operation": "inspect"})))
        self.assertTrue(result["ok"], result)
        warning = next(event for event in events if event.get("level") == "warning")
        self.assertIn("[링크]", warning["message"])
        self.assertNotIn("secret", json.dumps(events))

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
