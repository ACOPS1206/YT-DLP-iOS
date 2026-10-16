"""One CLI argument pipeline for on-device yt-dlp downloads."""
import contextlib
import io
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


def build_arguments(request):
    """Translate UI choices to CLI tokens; custom arguments replace selection."""
    raw = str(request.get("custom_arguments") or "").strip()
    if raw:
        tokens = shlex.split(raw)
        if tokens and tokens[0] == "yt-dlp":
            tokens.pop(0)
        return tokens
    # Legacy share-inbox requests remain readable, without another execution path.
    preset = str(request.get("preset_alias") or "").strip()
    if preset:
        return ["-t", preset]
    if request.get("ytdlp_defaults"):
        return []
    kind = request.get("format", "MP4")
    if kind not in ("MP4", "M4A"):
        raise ValueError("지원하지 않는 파일 형식입니다.")
    extension = str(request.get("output_extension") or "").strip().lower().lstrip(".")
    if extension and not re.fullmatch(r"[a-z0-9]{1,10}", extension):
        raise ValueError("확장자는 점(.) 없이 영문자와 숫자만 입력해 주세요.")
    ceiling = int(request.get("quality") or 0)
    if ceiling and not 144 <= ceiling <= 4320:
        raise ValueError("화질은 144~4320p 범위로 입력해 주세요.")
    selector = "b" if kind == "MP4" else "ba"
    if extension:
        selector += f"[ext={extension}]"
    if kind == "MP4" and ceiling:
        selector += f"[height<={ceiling}]"
    arguments = ["-f", selector]
    if request.get("download_subtitles"):
        arguments += ["--write-subs", "--sub-langs", request.get("subtitle_languages") or "ko,en"]
        if request.get("automatic_subtitles", True):
            arguments += ["--write-auto-subs"]
    return arguments


def command_options(parse_options, arguments):
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            parsed = parse_options(["--ignore-config", *arguments])
    except (SystemExit, Exception) as error:
        raise ValueError("yt-dlp 인수를 확인해 주세요. --help/-U는 다운로드 인수가 아닙니다.") from error
    if parsed.urls:
        raise ValueError("링크는 링크 입력란에 넣고, 커스텀 명령에는 옵션만 입력해 주세요.")
    options = parsed.ydl_opts
    options["postprocessors"] = [pp for pp in options.get("postprocessors", [])
                                 if not (pp.get("key") == "FFmpegConcat" and pp.get("only_multi_video"))]
    # Embedded CPython cannot spawn desktop tools. Fail before any transfer.
    if any(pp.get("key", "").startswith(("FFmpeg", "Exec"))
           for pp in options.get("postprocessors", [])) or options.get("external_downloader"):
        raise ValueError("이 명령은 FFmpeg 또는 외부 실행 파일이 필요합니다. 현재 iOS 엔진은 원본 파일 저장만 지원합니다.")
    if getattr(parsed.options, "update_self", False):
        raise ValueError("엔진 업데이트는 설정의 업데이트 버튼을 사용해 주세요.")
    return options


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


_SIDECAR_EXTENSIONS = {
    "json", "description", "vtt", "srt", "ass", "lrc", "ttml", "srv1", "srv2", "srv3",
    "jpg", "jpeg", "png", "webp", "gif", "avif", "webloc", "desktop", "url",
}


def _single_download_file(folder, info=None, ydl=None):
    candidates = []

    def add(path):
        if not path:
            return
        path = os.path.abspath(os.path.expanduser(str(path)))
        if os.path.commonpath((os.path.realpath(folder), os.path.realpath(path))) != os.path.realpath(folder):
            return
        if os.path.isfile(path) and path not in candidates:
            candidates.append(path)

    if isinstance(info, dict):
        add(info.get("filepath"))
        add(info.get("_filename"))
        for key in ("requested_downloads", "requested_formats"):
            for item in info.get(key) or []:
                if isinstance(item, dict):
                    add(item.get("filepath"))
                    add(item.get("_filename"))
        for source, destination in (info.get("__files_to_move") or {}).items():
            add(destination or source)
        if ydl is not None:
            try:
                add(ydl.prepare_filename(info))
            except Exception:
                pass

    if os.path.isdir(folder):
        for root, _, names in os.walk(folder):
            for name in names:
                if name.endswith((".part", ".ytdl", ".temp")):
                    continue
                add(os.path.join(root, name))

    media = [path for path in candidates
             if os.path.splitext(path)[1].lower().lstrip(".") not in _SIDECAR_EXTENSIONS]
    if len(media) == 1:
        return media[0]
    if len(media) > 1:
        raise ValueError("yt-dlp가 여러 미디어 파일을 만들었습니다. 현재 보관함에는 한 번에 한 파일만 가져올 수 있습니다.")
    if not candidates:
        raise ValueError("yt-dlp 다운로드 결과 파일을 찾을 수 없습니다.")
    raise ValueError("yt-dlp가 여러 결과 파일을 만들었지만 저장할 미디어 파일을 하나로 결정할 수 없습니다.")


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
        arguments = build_arguments(request)
        options = command_options(parse_options, arguments)
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
            def finite(value):
                return value if isinstance(value, (float, int)) and math.isfinite(value) else None
            emit("downloading", progress=finite(value), speed=finite(event.get("speed")),
                 eta=finite(event.get("eta")))

        user_filter = options.get("match_filter")
        def match_filter(info, *, incomplete=False):
            checkpoint()
            if info.get("requested_formats"):
                raise ValueError("이 선택은 영상·오디오 병합이 필요합니다. -f best 또는 단일 원본 포맷을 선택해 주세요.")
            if info.get("is_live"):
                raise ValueError("진행 중인 라이브 영상은 지원하지 않습니다.")
            if (info.get("age_limit") or 0) >= 18:
                raise ValueError("이 콘텐츠는 지원하지 않습니다.")
            emit("metadata", info=media_info(info))
            return user_filter(info, incomplete=incomplete) if user_filter else None

        options.update(logger=Logger(), progress_hooks=[hook], match_filter=match_filter,
                       noplaylist=True, playlistend=1, quiet=True, noprogress=True,
                       cachedir=False, js_runtimes={}, remote_components=[],
                       fixup="never", age_limit=17)
        downloading = request.get("operation") == "download"
        folder = request.get("directory", "")
        if downloading:
            os.makedirs(folder, exist_ok=True)
            # App owns staging; CLI -o/-P must not move or overwrite unrelated files.
            options["paths"] = {"home": folder, "temp": folder}
            options["outtmpl"] = {"default": os.path.join(folder, "media.%(ext)s")}
        log("커스텀 yt-dlp 인수로 실행" if request.get("custom_arguments") else "yt-dlp " + shlex.join(arguments))
        with YoutubeDL(options) as ydl:
            info = ydl.extract_info(url, download=downloading)
            checkpoint()
            if not info or info.get("_type") in ("playlist", "multi_video"):
                raise ValueError("한 개의 동영상 링크를 입력해 주세요.")
            summary = media_info(info)
            emit("metadata", info=summary)
            result = {"ok": True, "info": summary, "version": __version__}
            if downloading:
                result["file"] = _single_download_file(folder, info, ydl)
                result["media_type"] = "audio" if info.get("vcodec") == "none" else "video"
                subtitles = [entry.get("filepath") for entry in (info.get("requested_subtitles") or {}).values()
                             if entry.get("filepath") and os.path.isfile(entry["filepath"])]
                # Current library stores one subtitle. Keep deterministic language order.
                if subtitles:
                    result["subtitle"] = subtitles[0]
                if len(subtitles) > 1:
                    log("보관함에는 첫 번째 자막 파일만 함께 저장합니다.", "warning")
                log("다운로드 완료")
            return json.dumps(result, allow_nan=False)
    except Cancelled:
        return json.dumps({"ok": False, "cancelled": True})
    except Exception as error:
        if bridge.is_cancelled():
            return json.dumps({"ok": False, "cancelled": True})
        return json.dumps({"ok": False, "error": str(error)[:1200]})
