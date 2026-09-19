#!/usr/bin/env python3
"""Fetch the pinned iOS Python runtime and pure-Python dependencies."""
import argparse
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
PYTHON_URL = "https://github.com/beeware/Python-Apple-support/releases/download/3.13-b14/Python-3.13-iOS-support.b14.tar.gz"
PYTHON_SHA256 = "8b5cb76ef8d8a2946052479358eeec9d54b4496cb60920e175ec1489b5cf7963"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dependencies-only", action="store_true")
    args = parser.parse_args()
    vendor = ROOT / "Vendor"
    vendor.mkdir(exist_ok=True)
    archive = vendor / "python-ios.tar.gz"
    if not (vendor / "Python.xcframework").exists():
        print("Downloading the pinned Python iOS runtime…", flush=True)
        if not archive.exists():
            with urllib.request.urlopen(PYTHON_URL, timeout=120) as response, archive.open("wb") as target:
                shutil.copyfileobj(response, target)
        digest = hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
        if digest != PYTHON_SHA256:
            raise SystemExit("Python runtime checksum mismatch. Remove Vendor/python-ios.tar.gz and retry.")
        with tempfile.TemporaryDirectory() as folder:
            with tarfile.open(archive, "r:gz") as package:
                package.extractall(folder, filter="data")
            framework = next(pathlib.Path(folder).rglob("Python.xcframework"), None)
            if framework is None:
                raise SystemExit("The runtime archive does not contain Python.xcframework.")
            shutil.copytree(framework, vendor / "Python.xcframework")
            # Preserve dependency license notices from the support archive.
            for name in ("VERSIONS", "LICENSE", "LICENSE.txt"):
                for source in pathlib.Path(folder).rglob(name):
                    if "Python.xcframework" not in source.parts:
                        shutil.copy2(source, vendor / name)
                        break
        archive.unlink()
    if not (vendor / "Python.xcframework/Info.plist").exists():
        raise SystemExit("Missing Python XCFramework metadata.")
    subprocess.run([sys.executable, "-m", "pip", "install", "--upgrade", "--no-compile", "--no-deps",
                    "--target", str(ROOT / "Python/app"), "-r", str(ROOT / "requirements-ios.txt")], check=True)
    if not args.dependencies_only:
        subprocess.run(["xcodegen", "generate"], cwd=ROOT, check=True)
        print("Open YTDLPGUI.xcodeproj in Xcode 26 or newer.")


if __name__ == "__main__":
    main()
