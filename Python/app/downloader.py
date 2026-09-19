"""On-device extraction/download. Swift AVFoundation handles MP4 muxing."""
import copy
import hashlib
import importlib
import json
import math
import os
import re
import shlex
import shutil
import sys
import tempfile
import time
import zipfile
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


class Cancelled(Exception):
    pass


def validate_url(value):
    parsed = urlsplit(value.strip())
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("올바른 http 또는 https 링크를 입력해 주세요.")
    if parsed.username or parsed.password:
        raise ValueError("인증 정보가 포함된 링크는 지원하지 않습니다.")
    return value.strip()


def compatible_video(fmt, ceiling):
    height = fmt.get("height") or 0
    codec = fmt.get("vcodec") or ""
    acodec = fmt.get("acodec") or "none"
    return (fmt.get("ext") == "mp4"
            and codec.startswith(("avc1", "h264"))
            and (acodec == "none" or acodec.startswith(("mp4a", "aac")))
            and fmt.get("protocol") in ("https", "http")
            and not fmt.get("has_drm")
            and (not ceiling or (height > 0 and height <= ceiling)))


def compatible_audio(fmt):
    return (fmt.get("ext") in ("m4a", "mp4")
            and (fmt.get("vcodec") or "none") == "none"
            and (fmt.get("acodec") or "").startswith(("mp4a", "aac"))
            and fmt.get("protocol") in ("https", "http")
            and not fmt.get("has_drm"))


def _format_by_id(formats, format_id, predicate, kind):
    if not format_id:
        return None
    match = next((fmt for fmt in formats if str(fmt.get("format_id")) == str(format_id)), None)
    if not match:
        raise ValueError(f"{kind} 형식 ID {format_id}을(를) 찾을 수 없습니다.")
    if not predicate(match):
        raise ValueError(f"형식 ID {format_id}은(는) iOS에서 저장 가능한 {kind} 형식이 아닙니다.")
    return match


def select_streams(info, output_format, ceiling, video_format_id="", audio_format_id=""):
    formats = info.get("formats") or [info]
    audio = (_format_by_id(formats, audio_format_id, compatible_audio, "오디오")
             or max((fmt for fmt in formats if compatible_audio(fmt)),
                    key=lambda fmt: (fmt.get("abr") or 0, fmt.get("tbr") or 0), default=None))
    if output_format == "M4A":
        if not audio:
            raise ValueError("이 링크에는 저장 가능한 M4A 오디오가 없습니다.")
        return None, audio
    video = (_format_by_id(formats, video_format_id,
                           lambda fmt: compatible_video(fmt, 0), "비디오")
             or max((fmt for fmt in formats if compatible_video(fmt, ceiling)),
                    key=lambda fmt: (fmt.get("height") or 0, fmt.get("fps") or 0, fmt.get("tbr") or 0),
                    default=None))
    if not video:
        raise ValueError("선택한 화질에 맞는 H.264 MP4 원본이 없습니다.")
    if video.get("acodec") not in (None, "none") and not audio_format_id:
        return video, None
    if not audio:
        # Prefer a complete compatible video over silently losing its sound.
        complete = [fmt for fmt in formats if compatible_video(fmt, ceiling)
                    and fmt.get("acodec") not in (None, "none")]
        if complete:
            return max(complete, key=lambda fmt: (fmt.get("height") or 0, fmt.get("tbr") or 0)), None
        raise ValueError("영상과 함께 저장할 호환 오디오가 없습니다.")
    return video, audio


def parse_custom_arguments(value):
    """Translate a small, non-shell yt-dlp argument allowlist to API options."""
    tokens = shlex.split(value or "")
    options = {}
    headers = {}
    specs = {
        "--socket-timeout": ("socket_timeout", "number"),
        "--retries": ("retries", "count"),
        "--fragment-retries": ("fragment_retries", "count"),
        "--user-agent": ("User-Agent", "header_text"),
        "--referer": ("Referer", "header_text"),
        "--add-header": ("http_headers", "header"),
    }
    index = 0
    while index < len(tokens):
        token = tokens[index]
        key, separator, inline = token.partition("=")
        if key not in specs:
            raise ValueError(f"지원하지 않는 추가 인자입니다: {key}")
        if separator:
            raw = inline
        else:
            index += 1
            if index >= len(tokens) or tokens[index].startswith("--"):
                raise ValueError(f"{key} 뒤에 값이 필요합니다.")
            raw = tokens[index]
        destination, kind = specs[key]
        if kind == "number":
            try:
                parsed = float(raw)
            except ValueError as error:
                raise ValueError(f"{key} 값은 숫자여야 합니다.") from error
            if not 1 <= parsed <= 300:
                raise ValueError(f"{key} 값은 1~300 사이여야 합니다.")
            options[destination] = parsed
        elif kind == "count":
            if raw == "infinite":
                options[destination] = float("inf")
            else:
                try:
                    parsed = int(raw)
                except ValueError as error:
                    raise ValueError(f"{key} 값은 정수 또는 infinite여야 합니다.") from error
                if not 0 <= parsed <= 100:
                    raise ValueError(f"{key} 값은 0~100 사이여야 합니다.")
                options[destination] = parsed
        elif kind == "header":
            name, colon, header_value = raw.partition(":")
            if not colon or not name.strip() or "\n" in raw or "\r" in raw:
                raise ValueError("--add-header 값은 '이름: 값' 형식이어야 합니다.")
            headers[name.strip()] = header_value.strip()
        elif kind == "header_text":
            if not raw.strip() or "\n" in raw or "\r" in raw:
                raise ValueError(f"{key} 값이 올바르지 않습니다.")
            headers[destination] = raw
        else:
            if not raw.strip() or "\n" in raw or "\r" in raw:
                raise ValueError(f"{key} 값이 올바르지 않습니다.")
            options[destination] = raw
        index += 1
    if headers:
        options["http_headers"] = headers
    return options


def select_subtitle(info, languages, automatic=True):
    requested = [part.strip() for part in (languages or "").split(",") if part.strip()]
    if not requested:
        requested = ["ko", "en"]
    sources = [(info.get("subtitles") or {}, False)]
    if automatic:
        sources.append((info.get("automatic_captions") or {}, True))
    for language in requested:
        for captions, is_automatic in sources:
            key = next((name for name in captions if name == language), None)
            key = key or next((name for name in captions if name.split("-")[0] == language.split("-")[0]), None)
            if not key:
                continue
            choices = captions.get(key) or []
            choice = next((entry for entry in choices if entry.get("ext") == "vtt"), None)
            choice = choice or next((entry for entry in choices if entry.get("url")), None)
            if choice and choice.get("url"):
                return key, choice, is_automatic
    return None


def install_latest_engine(root, emit):
    os.makedirs(root, exist_ok=True)
    metadata_request = Request("https://pypi.org/pypi/yt-dlp/json", headers={"User-Agent": "YT-DLP-iOS-Updater/1"})
    with urlopen(metadata_request, timeout=30) as response:
        metadata = json.load(response)
    version = metadata["info"]["version"]
    files = metadata.get("urls") or []
    wheel = next((item for item in files
                  if item.get("packagetype") == "bdist_wheel"
                  and item.get("filename", "").endswith("py3-none-any.whl")), None)
    if not wheel:
        raise ValueError("설치 가능한 yt-dlp wheel을 찾지 못했습니다.")
    expected = (wheel.get("digests") or {}).get("sha256")
    if not expected:
        raise ValueError("업데이트 파일의 SHA-256 정보가 없습니다.")
    final = os.path.join(root, version)
    if os.path.isfile(os.path.join(final, "yt_dlp", "__init__.py")):
        _write_current(root, version)
        return version, False
    staging = tempfile.mkdtemp(prefix=f".{version}-", dir=root)
    archive = os.path.join(staging, "package.whl")
    try:
        request = Request(wheel["url"], headers={"User-Agent": "YT-DLP-iOS-Updater/1"})
        digest = hashlib.sha256()
        with urlopen(request, timeout=60) as response, open(archive, "wb") as output:
            total = int(response.headers.get("Content-Length") or 0)
            received = 0
            while True:
                chunk = response.read(128 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                digest.update(chunk)
                received += len(chunk)
                emit("updating", progress=(received / total if total else None))
        if digest.hexdigest().lower() != expected.lower():
            raise ValueError("업데이트 파일의 SHA-256 검증에 실패했습니다.")
        with zipfile.ZipFile(archive) as package:
            root_real = os.path.realpath(staging)
            for member in package.infolist():
                target = os.path.realpath(os.path.join(staging, member.filename))
                if not target.startswith(root_real + os.sep):
                    raise ValueError("업데이트 파일에 안전하지 않은 경로가 있습니다.")
            package.extractall(staging)
        os.remove(archive)
        if not os.path.isfile(os.path.join(staging, "yt_dlp", "__init__.py")):
            raise ValueError("업데이트에 yt-dlp 패키지가 없습니다.")
        if os.path.exists(final):
            shutil.rmtree(final)
        os.replace(staging, final)
        _write_current(root, version)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    for name in os.listdir(root):
        path = os.path.join(root, name)
        if name not in (version, "current") and not name.startswith(".") and os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)
    return version, True


def _write_current(root, version):
    temporary = os.path.join(root, ".current.tmp")
    with open(temporary, "w", encoding="utf-8") as marker:
        marker.write(version)
    os.replace(temporary, os.path.join(root, "current"))


def load_ytdlp():
    """Load the updated package, falling back to the bundled copy if startup fails."""
    try:
        module = importlib.import_module("yt_dlp")
        version = importlib.import_module("yt_dlp.version").__version__
        importlib.import_module("ios_jsc")
        return module.YoutubeDL, version
    except Exception as updated_error:
        root = os.environ.get("YTDLP_UPDATE_ROOT")
        active_update = root and any(
            os.path.realpath(path).startswith(os.path.realpath(root) + os.sep)
            for path in sys.path if path)
        if not active_update:
            raise
        try:
            os.remove(os.path.join(root, "current"))
        except FileNotFoundError:
            pass
        sys.path[:] = [path for path in sys.path if not (
            path and os.path.realpath(path).startswith(os.path.realpath(root) + os.sep))]
        for name in list(sys.modules):
            if name == "yt_dlp" or name.startswith("yt_dlp.") or name == "ios_jsc":
                sys.modules.pop(name, None)
        importlib.invalidate_caches()
        try:
            module = importlib.import_module("yt_dlp")
            version = importlib.import_module("yt_dlp.version").__version__
            importlib.import_module("ios_jsc")
            return module.YoutubeDL, version
        except Exception:
            raise updated_error


def media_info(info):
    duration = info.get("duration")
    if duration is not None and not math.isfinite(duration):
        duration = None
    return {"title": info.get("title") or "다운로드",
            "author": info.get("uploader") or info.get("channel") or "",
            "duration": duration, "thumbnail": info.get("thumbnail")}


def run(request_json):
    import _ios_bridge as bridge
    def emit(phase, **values):
        bridge.emit(json.dumps({"phase": phase, **values}, allow_nan=False))

    def checkpoint():
        if bridge.is_cancelled():
            raise Cancelled()

    def log(message, level="info"):
        # Signed media URLs and sandbox paths need not appear on the Lock Screen.
        cleaned = re.sub(r"https?://\S+", "[링크]", str(message))
        cleaned = re.sub(r"/(?:private/)?var/\S+", "[경로]", cleaned)
        emit("log", message=cleaned[:400], level=level)

    class Logger:
        def debug(self, message):
            if not str(message).startswith("[debug]"):
                log(message)

        def info(self, message):
            log(message)

        def warning(self, message):
            log(message, "warning")

        def error(self, message):
            log(message, "error")

    request = json.loads(request_json)
    try:
        checkpoint()
        if request.get("operation") == "update_engine":
            version, changed = install_latest_engine(request["directory"], emit)
            return json.dumps({"ok": True, "version": version, "updated": changed}, allow_nan=False)

        YoutubeDL, __version__ = load_ytdlp()

        url = validate_url(request["url"])
        emit("extracting")
        options = {
            "noplaylist": True, "quiet": True, "no_warnings": False, "noprogress": True,
            "logger": Logger(),
            # The app chooses compatible streams itself and combines them with
            # AVFoundation. An explicit single-stream selector prevents yt-dlp
            # from probing for an external ffmpeg executable on iOS.
            "format": "best",
            "cachedir": False, "socket_timeout": 15,
            "retries": 2, "fragment_retries": 2,
            "js_runtimes": {}, "remote_components": [],
            # web/web_safari may expose only SABR/storyboard entries without a
            # GVS PO Token. Prefer a client that currently exposes direct media
            # URLs on-device, and let our own select_streams() choose H.264/AAC.
            "extractor_args": {"youtube": {"player_client": ["visionos", "android"]}},
            # Keep metadata available even if YouTube temporarily exposes no
            # downloadable A/V formats, so we can return our own clear error.
            "ignore_no_formats_error": True,
            "postprocessors": [], "fixup": "never",
            "age_limit": 17, "overwrites": True,
        }
        options.update(parse_custom_arguments(request.get("custom_arguments", "")))
        with YoutubeDL(options) as ydl:
            info = ydl.extract_info(url, download=False)
            checkpoint()
            if not info or info.get("_type") in ("playlist", "multi_video"):
                raise ValueError("한 개의 동영상 링크를 입력해 주세요.")
            if (info.get("age_limit") or 0) >= 18:
                raise ValueError("이 콘텐츠는 지원하지 않습니다.")
            if info.get("is_live"):
                raise ValueError("진행 중인 라이브 영상은 지원하지 않습니다.")
            summary = media_info(info)
            emit("metadata", info=summary)
            log("동영상 정보 확인 완료")
            if request["operation"] == "inspect":
                return json.dumps({"ok": True, "info": summary, "version": __version__}, allow_nan=False)

            output_format = request.get("format", "MP4")
            if output_format not in ("MP4", "M4A"):
                raise ValueError("지원하지 않는 저장 형식입니다.")
            video, audio = select_streams(info, output_format, int(request.get("quality", 0)),
                                          request.get("video_format_id", "").strip(),
                                          request.get("audio_format_id", "").strip())
            if video:
                log(f"선택한 원본: H.264 MP4 · {video.get('height') or '?'}p")
            if audio:
                log("선택한 오디오: 원본 AAC")
            folder = request["directory"]
            os.makedirs(folder, exist_ok=True)
            streams = [(name, stream) for name, stream in (("video", video), ("audio", audio)) if stream]
            paths = {}

            for index, (name, stream) in enumerate(streams):
                checkpoint()
                log("동영상 원본 다운로드 시작" if name == "video" else "오디오 원본 다운로드 시작")
                last_emit = [0.0]

                def hook(event):
                    checkpoint()
                    now = time.monotonic()
                    if now - last_emit[0] < 0.15 and event.get("status") != "finished":
                        return
                    last_emit[0] = now
                    total = event.get("total_bytes") or event.get("total_bytes_estimate")
                    value = min(1.0, event.get("downloaded_bytes", 0) / total) if total else None
                    if event.get("status") == "finished":
                        value = 1.0
                    progress = (index + value) / len(streams) if value is not None else None
                    emit("downloading", progress=progress,
                         speed=event.get("speed"), eta=event.get("eta"))

                single = copy.deepcopy(info)
                for key in ("requested_formats", "requested_downloads", "__postprocessors", "_filename", "filepath"):
                    single.pop(key, None)
                single.update(stream)
                ydl.params["outtmpl"] = {"default": os.path.join(folder, name + ".%(ext)s")}
                ydl.params["progress_hooks"] = [hook]
                # YoutubeDL stores hooks separately from params.
                ydl._progress_hooks = [hook]
                ydl.process_info(single)
                checkpoint()
                path = ydl.prepare_filename(single)
                if not path or not os.path.isfile(path):
                    raise ValueError("다운로드 결과 파일을 찾을 수 없습니다.")
                paths[name] = path
                log("동영상 원본 다운로드 완료" if name == "video" else "오디오 원본 다운로드 완료")
            if request.get("download_subtitles"):
                selected = select_subtitle(info, request.get("subtitle_languages", ""),
                                           request.get("automatic_subtitles", True))
                if selected:
                    language, subtitle, is_automatic = selected
                    extension = re.sub(r"[^a-zA-Z0-9]", "", subtitle.get("ext") or "vtt") or "vtt"
                    path = os.path.join(folder, f"subtitle.{language}.{extension}")
                    log(f"{'자동 ' if is_automatic else ''}자막 다운로드 시작 · {language}")
                    with ydl.urlopen(subtitle["url"]) as response, open(path, "wb") as output:
                        shutil.copyfileobj(response, output)
                    paths["subtitle"] = path
                    log("자막 다운로드 완료")
                else:
                    log("선택한 언어의 자막을 찾지 못했습니다.", "warning")
            return json.dumps({"ok": True, "info": summary, "version": __version__, **paths}, allow_nan=False)
    except Cancelled:
        return json.dumps({"ok": False, "cancelled": True})
    except Exception as error:
        if bridge.is_cancelled():
            return json.dumps({"ok": False, "cancelled": True})
        return json.dumps({"ok": False, "error": str(error)[:1200]})
