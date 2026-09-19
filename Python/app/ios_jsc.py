"""Bundled yt-dlp EJS scripts run inside Apple's JavaScriptCore.

This adapter targets yt-dlp 2026.08.19. No command-line JS executable is used.
The provider API is internal; validate this adapter when updating yt-dlp.
"""
import _ios_bridge
from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP, ScriptSource
from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeProviderError, register_preference, register_provider,
)


@register_provider
class AppleJavaScriptCoreJCP(EJSBaseJCP):
    PROVIDER_NAME = "apple-javascriptcore"
    JS_RUNTIME_NAME = "javascriptcore"

    def is_available(self):
        return self._available

    def _iter_script_sources(self):
        # Only scripts shipped with the application are eligible.
        yield ScriptSource.PYPACKAGE, self._pypackage_source
        yield ScriptSource.BUILTIN, self._builtin_source

    def _run_js_runtime(self, stdin, /):
        if _ios_bridge.is_cancelled():
            raise JsChallengeProviderError("작업이 취소되었습니다.")
        try:
            return _ios_bridge.evaluate_js(stdin)
        except RuntimeError as error:
            raise JsChallengeProviderError(str(error)) from error


@register_preference(AppleJavaScriptCoreJCP)
def preference(provider, requests):
    return 1000
