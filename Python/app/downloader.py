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


def _direct_format(fmt):
    return (fmt.get("protocol") in ("https", "http", "m3u8", "m3u8_native", "http_dash_segments")
            and not fmt.get("has_drm"))


def _within_ceiling(fmt, ceiling):
    height = fmt.get("height") or 0
    return not ceiling or (height > 0 and height <= ceiling)


def _normalise_extension(value):
    extension = (value or "").strip().lower().lstrip(".")
    if not extension:
        return ""
    if not re.fullmatch(r"[a-z0-9]{1,10}", extension):
        raise ValueError("확장자는 점(.) 없이 영문자와 숫자만 입력해 주세요.")
    return extension


def _has_video(fmt):
    return (fmt.get("vcodec") or "none") != "none"


def _has_audio(fmt):
    return (fmt.get("acodec") or "none") != "none"


def _video_key(fmt):
    return (fmt.get("height") or 0, fmt.get("fps") or 0, fmt.get("tbr") or 0,
            fmt.get("filesize") or fmt.get("filesize_approx") or 0)


def _audio_key(fmt):
    return (fmt.get("abr") or 0, fmt.get("tbr") or 0, fmt.get("asr") or 0)


def compatible_video(fmt, ceiling):
    codec = fmt.get("vcodec") or ""
    acodec = fmt.get("acodec") or "none"
    return (fmt.get("ext") == "mp4"
            and codec.startswith(("avc1", "h264"))
            and (acodec == "none" or acodec.startswith(("mp4a", "aac")))
            and _direct_format(fmt)
            and _within_ceiling(fmt, ceiling))


def compatible_audio(fmt):
    return (fmt.get("ext") in ("m4a", "mp4")
            and not _has_video(fmt)
            and (fmt.get("acodec") or "").startswith(("mp4a", "aac"))
            and _direct_format(fmt))


def _generic_video(fmt, ceiling, extension="", require_audio=None):
    if not (_has_video(fmt) and _direct_format(fmt) and _within_ceiling(fmt, ceiling)):
        return False
    if extension and (fmt.get("ext") or "").lower() != extension:
        return False
    if require_audio is True and not _has_audio(fmt):
        return False
    if require_audio is False and _has_audio(fmt):
        return False
    return True


def _generic_audio(fmt, extension=""):
    if _has_video(fmt) or not _has_audio(fmt) or not _direct_format(fmt):
        return False
    return not extension or (fmt.get("ext") or "").lower() == extension


def select_streams(info, output_format, ceiling, video_extension="", audio_extension="", original_format=False):
    formats = info.get("formats") or [info]
    video_extension = _normalise_extension(video_extension)
    audio_extension = _normalise_extension(audio_extension)

    if output_format == "M4A":
        if original_format or audio_extension:
            candidates = [fmt for fmt in formats if _generic_audio(fmt, audio_extension)]
            if not candidates:
                label = f".{audio_extension}" if audio_extension else "원본"
                raise ValueError(f"이 링크에는 저장 가능한 {label} 오디오가 없습니다.")
            return None, max(candidates, key=_audio_key)

        audio = max((fmt for fmt in formats if compatible_audio(fmt)), key=_audio_key, default=None)
        if audio:
            return None, audio
        fallback = max((fmt for fmt in formats if _generic_audio(fmt)), key=_audio_key, default=None)
        if fallback:
            return None, fallback
        raise ValueError("이 링크에는 저장 가능한 오디오 원본이 없습니다.")

    if original_format:
        candidates = [fmt for fmt in formats
                      if _generic_video(fmt, ceiling, video_extension, require_audio=True)]
        if not candidates:
            label = f".{video_extension}" if video_extension else "원본"
            raise ValueError(f"선택한 화질에 맞는 영상+오디오 {label} 스트림이 없습니다.")
        return max(candidates, key=_video_key), None

    if video_extension and video_extension != "mp4":
        candidates = [fmt for fmt in formats
                      if _generic_video(fmt, ceiling, video_extension, require_audio=True)]
        if not candidates:
            raise ValueError(f"선택한 화질에 맞는 .{video_extension} 영상+오디오 원본이 없습니다.")
        return max(candidates, key=_video_key), None

    if audio_extension:
        audio_candidates = [fmt for fmt in formats if _generic_audio(fmt, audio_extension)]
        audio = max(audio_candidates, key=_audio_key, default=None)
    else:
        audio = max((fmt for fmt in formats if compatible_audio(fmt)), key=_audio_key, default=None)

    h264 = max((fmt for fmt in formats if compatible_video(fmt, ceiling)),
               key=_video_key, default=None)
    if h264:
        if _has_audio(h264):
            return h264, None
        if audio:
            return h264, audio
        complete_h264 = max((fmt for fmt in formats
                             if compatible_video(fmt, ceiling) and _has_audio(fmt)),
                            key=_video_key, default=None)
        if complete_h264:
            return complete_h264, None

    complete_mp4 = max((fmt for fmt in formats
                        if _generic_video(fmt, ceiling, "mp4", require_audio=True)),
                       key=_video_key, default=None)
    if complete_mp4:
        return complete_mp4, None

    if video_extension == "mp4":
        raise ValueError("선택한 화질에 맞는 MP4 영상+오디오 원본이 없습니다.")

    fallback = max((fmt for fmt in formats
                    if _generic_video(fmt, ceiling, require_audio=True)),
                   key=_video_key, default=None)
    if fallback:
        return fallback, None
    raise ValueError("선택한 화질에 맞는 저장 가능한 영상+오디오 원본이 없습니다.")

PRESET_ALIASES = ("mp3", "aac", "mp4", "mkv", "sleep")


def parse_custom_arguments(value):
    """Translate a small, non-shell yt-dlp argument allowlist to API options."""
    tokens = shlex.split(value or "")
    options = {}
    headers = {}
    presets = []
    specs = {
        "--socket-timeout": ("socket_timeout", "number"),
        "--retries": ("retries", "count"),
        "--fragment-retries": ("fragment_retries", "count"),
        "--user-agent": ("User-Agent", "header_text"),
        "--referer": ("Referer", "header_text"),
        "--add-header": ("http_headers", "header"),
        "-t": ("_preset_aliases", "preset"),
        "--preset-alias": ("_preset_aliases", "preset"),
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
        if kind == "preset":
            preset = raw.strip().lower()
            if preset not in PRESET_ALIASES:
                raise ValueError(
                    f"지원하지 않는 -t 프리셋입니다: {preset}. "
                    f"사용 가능: {', '.join(PRESET_ALIASES)}")
            presets.append(preset)
        elif kind == "number":
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
    if presets:
        options["_preset_aliases"] = presets
    return options


def resolve_preset_aliases(parse_options, presets):
    """Resolve yt-dlp's built-in -t presets to the exact YoutubeDL API delta."""
    if not presets:
        return {}
    arguments = []
    for preset in presets:
        arguments.extend(("-t", preset))
    baseline = parse_options([]).ydl_opts
    selected = parse_options(arguments).ydl_opts
    return {key: value for key, value in selected.items() if baseline.get(key) != value}


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
        return module.YoutubeDL, module.parse_options, version
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
            return module.YoutubeDL, module.parse_options, version
        except Exception:
            raise updated_error


def media_info(info):
    duration = info.get("duration")
    if duration is not None and not math.isfinite(duration):
        duration = None
    return {"title": info.get("title") or "다운로드",
            "author": info.get("uploader") or info.get("channel") or "",
            "duration": duration, "thumbnail": info.get("thumbnail")}


def _single_download_file(folder):
    candidates = []
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            continue
        if name.endswith((".part", ".ytdl", ".temp")):
            continue
        candidates.append(path)
    if not candidates:
        raise ValueError("yt-dlp 기본 다운로드 결과 파일을 찾을 수 없습니다.")
    if len(candidates) > 1:
        raise ValueError("yt-dlp가 여러 원본 파일을 만들었습니다. 이 링크의 기본 선택은 FFmpeg 병합이 필요할 수 있습니다.")
    return candidates[0]


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

        YoutubeDL, parse_options, __version__ = load_ytdlp()

        url = validate_url(request["url"])
        emit("extracting")
        ytdlp_defaults = bool(request.get("ytdlp_defaults", False))

        def default_hook(event):
            checkpoint()
            total = event.get("total_bytes") or event.get("total_bytes_estimate")
            value = min(1.0, event.get("downloaded_bytes", 0) / total) if total else None
            if event.get("status") == "finished":
                value = 1.0
            emit("downloading", progress=value, speed=event.get("speed"), eta=event.get("eta"))

        options = {
            "noplaylist": True, "quiet": True, "no_warnings": False, "noprogress": True,
            "logger": Logger(), "cachedir": False,
            "js_runtimes": {}, "remote_components": [],
            "age_limit": 17, "overwrites": True,
        }
        if ytdlp_defaults:
            # Keep only app-integration settings. In particular, do not pass a
            # format selector, quality ceiling, extension preference, custom
            # yt-dlp arguments, extractor-client override, or postprocessor policy.
            if request.get("operation") == "download":
                folder = request["directory"]
                os.makedirs(folder, exist_ok=True)
                options["outtmpl"] = {"default": os.path.join(folder, "yt-dlp.%(ext)s")}
                options["progress_hooks"] = [default_hook]
        else:
            options.update({
                # The app chooses compatible streams itself and combines them
                # with AVFoundation. "best" here only keeps extraction on a
                # single stream while the app performs its own final selection.
                "format": "best",
                "socket_timeout": 15, "retries": 2, "fragment_retries": 2,
                "hls_prefer_native": True,
                "extractor_args": {"youtube": {"player_client": ["visionos", "android"]}},
                "ignore_no_formats_error": True,
                "postprocessors": [], "fixup": "never",
            })
            custom_options = parse_custom_arguments(request.get("custom_arguments", ""))
            preset_aliases = custom_options.pop("_preset_aliases", [])
            if preset_aliases:
                options.update(resolve_preset_aliases(parse_options, preset_aliases))
            options.update(custom_options)
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

            if ytdlp_defaults:
                log("yt-dlp 기본 선택 모드 · 포맷/화질 선택 인수 없이 다운로드")
                downloaded = ydl.extract_info(url, download=True)
                checkpoint()
                if not downloaded:
                    raise ValueError("yt-dlp 기본 다운로드 결과를 읽을 수 없습니다.")
                path = _single_download_file(request["directory"])
                log(f"yt-dlp 기본 다운로드 완료 · {(os.path.splitext(path)[1] or '원본').lstrip('.').upper()}")
                return json.dumps({"ok": True, "info": summary, "version": __version__,
                                   "file": path}, allow_nan=False)

            output_format = request.get("format", "MP4")
            if output_format not in ("MP4", "M4A"):
                raise ValueError("지원하지 않는 저장 형식입니다.")
            original_format = bool(request.get("original_format", False))
            video, audio = select_streams(info, output_format, int(request.get("quality", 0)),
                                          request.get("video_extension", ""),
                                          request.get("audio_extension", ""),
                                          original_format)
            if video:
                extension = (video.get("ext") or "?").upper()
                codec = video.get("vcodec") or "unknown"
                height = video.get("height") or "?"
                if original_format:
                    log(f"원본 포맷 선택: {extension} · {height}p")
                elif extension != "MP4" or not codec.startswith(("avc1", "h264")):
                    log(f"H.264 MP4 대신 {extension} 원본으로 자동 대체 · {height}p", "warning")
                else:
                    log(f"선택한 원본: H.264 MP4 · {height}p")
            if audio:
                extension = (audio.get("ext") or "?").upper()
                codec = audio.get("acodec") or "unknown"
                log(f"선택한 오디오: {extension} · {codec}")
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
