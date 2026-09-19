"""On-device extraction/download. Swift AVFoundation handles MP4 muxing."""
import copy
import json
import math
import os
import re
import time
from urllib.parse import urlsplit


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


def select_streams(info, output_format, ceiling):
    formats = info.get("formats") or [info]
    audio = max((fmt for fmt in formats if compatible_audio(fmt)),
                key=lambda fmt: (fmt.get("abr") or 0, fmt.get("tbr") or 0), default=None)
    if output_format == "M4A":
        if not audio:
            raise ValueError("이 링크에는 저장 가능한 M4A 오디오가 없습니다.")
        return None, audio
    video = max((fmt for fmt in formats if compatible_video(fmt, ceiling)),
                key=lambda fmt: (fmt.get("height") or 0, fmt.get("fps") or 0, fmt.get("tbr") or 0),
                default=None)
    if not video:
        raise ValueError("선택한 화질에 맞는 H.264 MP4 원본이 없습니다.")
    if video.get("acodec") not in (None, "none"):
        return video, None
    if not audio:
        # Prefer a complete compatible video over silently losing its sound.
        complete = [fmt for fmt in formats if compatible_video(fmt, ceiling)
                    and fmt.get("acodec") not in (None, "none")]
        if complete:
            return max(complete, key=lambda fmt: (fmt.get("height") or 0, fmt.get("tbr") or 0)), None
        raise ValueError("영상과 함께 저장할 호환 오디오가 없습니다.")
    return video, audio


def media_info(info):
    duration = info.get("duration")
    if duration is not None and not math.isfinite(duration):
        duration = None
    return {"title": info.get("title") or "다운로드",
            "author": info.get("uploader") or info.get("channel") or "",
            "duration": duration, "thumbnail": info.get("thumbnail")}


def run(request_json):
    import _ios_bridge as bridge
    from yt_dlp import YoutubeDL
    from yt_dlp.version import __version__
    import ios_jsc  # Registers the JavaScriptCore provider before extraction.

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
        url = validate_url(request["url"])
        emit("extracting")
        options = {
            "noplaylist": True, "quiet": True, "no_warnings": False, "noprogress": True,
            "logger": Logger(),
            "cachedir": False, "socket_timeout": 15,
            "retries": 2, "fragment_retries": 2,
            "js_runtimes": {}, "remote_components": [],
            "extractor_args": {"youtube": {"player_client": ["web", "web_safari"]}},
            "format": "bestvideo+bestaudio/best",
            "postprocessors": [], "fixup": "never",
            "age_limit": 17, "overwrites": True,
        }
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
            video, audio = select_streams(info, output_format, int(request.get("quality", 0)))
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
            return json.dumps({"ok": True, "info": summary, "version": __version__, **paths}, allow_nan=False)
    except Cancelled:
        return json.dumps({"ok": False, "cancelled": True})
    except Exception as error:
        if bridge.is_cancelled():
            return json.dumps({"ok": False, "cancelled": True})
        return json.dumps({"ok": False, "error": str(error)[:1200]})
