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

from downloader import (build_arguments, command_options, install_latest_engine,
                        run, validate_url)


class CommandTests(unittest.TestCase):
    def options(self, request):
        from yt_dlp import parse_options
        return command_options(parse_options, build_arguments(request))

    def test_video_extension_and_quality_are_cli_filters(self):
        self.assertEqual(self.options({"format": "MP4", "quality": 720,
                                      "output_extension": ".MP4"})["format"],
                         "b[ext=mp4][height<=720]")

    def test_audio_selects_original_not_conversion(self):
        options = self.options({"format": "M4A", "output_extension": "webm"})
        self.assertEqual(options["format"], "ba[ext=webm]")
        self.assertFalse(options["postprocessors"])

    def test_custom_command_overrides_ui(self):
        options = self.options({"custom_arguments": 'yt-dlp -f "worst[ext=mp4]" --concurrent-fragments 3',
                                "format": "M4A", "quality": 480, "output_extension": "opus",
                                "download_subtitles": True})
        self.assertEqual(options["format"], "worst[ext=mp4]")
        self.assertEqual(options["concurrent_fragment_downloads"], 3)
        self.assertFalse(options["writesubtitles"])

    def test_subtitles_go_through_cli_parser(self):
        options = self.options({"download_subtitles": True, "subtitle_languages": "en,ko"})
        self.assertTrue(options["writesubtitles"])
        self.assertTrue(options["writeautomaticsub"])
        self.assertEqual(options["subtitleslangs"], ["en", "ko"])

    def test_invalid_arguments_raise_instead_of_system_exit(self):
        for command in ('--not-a-real-option', '--help', '-f "unterminated',
                        '-f best https://example.com/extra', '-x --audio-format mp3',
                        '--exec "echo hello"', '-U'):
            with self.subTest(command=command), self.assertRaises(ValueError):
                self.options({"custom_arguments": command})

    def test_invalid_ui_values_do_not_silently_fallback(self):
        for request in ({"quality": 100}, {"output_extension": "../mp4"}, {"format": "???"}):
            with self.assertRaises(ValueError): self.options(request)

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
    def download_fixture(self, *, custom="", audio=False, ceiling=720, extension="", cancel=False, split=False, live=False, age=0, subtitles=False):
        from yt_dlp import YoutubeDL
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source = root / ("source.m4a" if audio else "source.mp4")
            source.write_bytes(b"fixture-media" * 8192)
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=folder))
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                base = f"http://127.0.0.1:{server.server_port}"
                info = {"id": "fixture", "title": "Local fixture", "extractor": "fixture",
                        "extractor_key": "Fixture", "webpage_url": base,
                        "is_live": live, "age_limit": age,
                        "formats": [{"format_id": "original", "url": f"{base}/{source.name}",
                                     "protocol": "http", "ext": "m4a" if audio else "mp4",
                                     "vcodec": "none" if audio else "avc1", "acodec": "mp4a",
                                     "height": None if audio else 720}]}
                if split:
                    info["formats"][0]["acodec"] = "none"
                    info["formats"].append({"format_id": "audio", "url": f"{base}/{source.name}",
                                            "ext": "m4a", "protocol": "http", "vcodec": "none", "acodec": "mp4a"})
                if subtitles:
                    (root / "subtitle.vtt").write_text("WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n")
                    info["subtitles"] = {"en": [{"ext": "vtt", "url": f"{base}/subtitle.vtt"}]}
                calls, events = [], []
                def extract(ydl, url, download=True):
                    calls.append(download)
                    return ydl.process_ie_result(info, download=download)
                def cancelled():
                    return cancel and any(e.get("phase") == "downloading" for e in events)
                with patch.object(YoutubeDL, "extract_info", autospec=True, side_effect=extract), \
                     patch.object(bridge, "emit", side_effect=lambda raw: events.append(json.loads(raw))), \
                     patch.object(bridge, "is_cancelled", side_effect=cancelled), \
                     patch("subprocess.Popen", side_effect=AssertionError("External process attempted")):
                    result = json.loads(run(json.dumps({"operation": "download", "url": base,
                        "format": "M4A" if audio else "MP4", "quality": ceiling,
                        "output_extension": extension, "custom_arguments": custom,
                        "download_subtitles": subtitles, "subtitle_languages": "en",
                        "directory": str(root / "output")})))
                self.assertEqual(calls, [True], "Do not extract the same URL twice")
                if result["ok"]:
                    self.assertEqual(pathlib.Path(result["file"]).read_bytes(), source.read_bytes())
                    self.assertEqual(result["media_type"], "audio" if audio else "video")
                    self.assertTrue(any(e.get("progress") == 1.0 for e in events))
                if result["ok"] and subtitles:
                    self.assertIn("Hello", pathlib.Path(result["subtitle"]).read_text())
                return result
            finally:
                server.shutdown(); server.server_close(); thread.join()

    def test_real_http_single_file_download(self):
        result = self.download_fixture(extension="mp4")
        self.assertTrue(result["ok"], result)

    def test_real_audio_download(self):
        result = self.download_fixture(audio=True)
        self.assertTrue(result["ok"], result)

    def test_custom_command_uses_same_download_path(self):
        result = self.download_fixture(custom='yt-dlp -f worst -o "ignored.mp3"')
        self.assertTrue(result["ok"], result)
        self.assertTrue(result["file"].endswith(".mp4"))

    def test_unavailable_extension_or_quality_fails_honestly(self):
        self.assertFalse(self.download_fixture(extension="webm")["ok"])
        self.assertFalse(self.download_fixture(ceiling=360)["ok"])

    def test_cancel_during_transfer(self):
        self.assertTrue(self.download_fixture(cancel=True)["cancelled"])

    def test_subtitle_download_is_preserved(self):
        result = self.download_fixture(subtitles=True)
        self.assertTrue(result["ok"], result)

    def test_split_command_returns_explicit_merge_error(self):
        result = self.download_fixture(custom="-f bv+ba", split=True)
        self.assertFalse(result["ok"])
        self.assertIn("병합", result["error"])

    def test_live_and_age_restrictions_apply_before_download(self):
        self.assertFalse(self.download_fixture(live=True)["ok"])
        self.assertFalse(self.download_fixture(age=18)["ok"])

    def test_no_download_command_does_not_claim_success(self):
        self.assertFalse(self.download_fixture(custom="--simulate")["ok"])

    def test_parse_error_returns_json_and_next_request_works(self):
        result = json.loads(run(json.dumps({"url": "https://example.com/video", "operation": "inspect",
                                           "custom_arguments": "--help"})))
        self.assertFalse(result["ok"])
        result = self.download_fixture()
        self.assertTrue(result["ok"], result)

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
        self.assertEqual(options["format"], "b")

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
