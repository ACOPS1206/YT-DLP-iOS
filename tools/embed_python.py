#!/usr/bin/env python3
"""Package Python extensions as iOS frameworks, following CPython 3.13's guide.

https://docs.python.org/3.13/using/ios.html#adding-python-to-an-ios-project
"""
import os
import pathlib
import plistlib
import shutil
import subprocess


def select_slice(framework, simulator):
    data = plistlib.loads((framework / "Info.plist").read_bytes())
    candidates = [row for row in data["AvailableLibraries"]
                  if row["SupportedPlatform"] == "ios"
                  and (row.get("SupportedPlatformVariant") == "simulator") == simulator]
    if len(candidates) != 1:
        raise RuntimeError("Expected one Python slice for the selected iOS platform.")
    return framework / candidates[0]["LibraryIdentifier"]


def platform_stdlib(selected, architecture):
    candidate = selected / f"lib-{architecture}" / "python3.13"
    if candidate.exists():
        return candidate
    available = sorted(selected.glob("lib-*/python3.13"))
    if len(available) == 1:
        return available[0]
    raise RuntimeError(f"Python 3.13 platform library for {architecture} is missing.")


def package(project, bundle, simulator, bundle_id, minimum_os, signing_identity=None,
            architecture="arm64"):
    framework = project / "Vendor/Python.xcframework"
    selected = select_slice(framework, simulator)
    library = bundle / "python/lib"
    if library.exists():
        shutil.rmtree(library)
    # BeeWare keeps the architecture-independent standard library at the
    # XCFramework root and each platform's extension modules in its slice.
    common = framework / "lib"
    if not (common / "python3.13/encodings").exists():
        raise RuntimeError("Expected shared Python 3.13 standard library is missing.")
    shutil.copytree(common, library, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    stdlib = library / "python3.13"
    shutil.copytree(platform_stdlib(selected, architecture), stdlib,
                    dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    frameworks = bundle / "Frameworks"
    frameworks.mkdir(exist_ok=True)
    generated = []
    bases = [stdlib / "lib-dynload", bundle / "app"]
    for base in bases:
        for extension in sorted(base.rglob("*.so")):
            relative = extension.relative_to(base)
            module = ".".join((*relative.parts[:-1], relative.name.split(".")[0]))
            target = frameworks / (module + ".framework")
            target.mkdir(exist_ok=True)
            binary = target / module
            marker = extension.with_suffix(".fwork")
            shutil.move(str(extension), binary)
            marker.write_text(binary.relative_to(bundle).as_posix() + "\n", encoding="utf-8")
            (target / (module + ".origin")).write_text(marker.relative_to(bundle).as_posix() + "\n", encoding="utf-8")
            platform = "iPhoneSimulator" if simulator else "iPhoneOS"
            metadata = {
                "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": module,
                "CFBundleIdentifier": (bundle_id + "." + module).replace("_", "-"),
                "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": module,
                "CFBundlePackageType": "FMWK", "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1", "CFBundleSupportedPlatforms": [platform],
                "MinimumOSVersion": minimum_os,
            }
            (target / "Info.plist").write_bytes(plistlib.dumps(metadata))
            manifest = extension.with_suffix(".xcprivacy")
            short_manifest = extension.with_name(extension.name.split(".")[0] + ".xcprivacy")
            for source in (manifest, short_manifest):
                if source.exists():
                    shutil.copy2(source, target / "PrivacyInfo.xcprivacy")
                    break
            generated.append(target)
    if signing_identity:
        for target in generated:
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", signing_identity,
                            "--timestamp=none", str(target)], check=True)
    return generated


def main():
    project = pathlib.Path(os.environ["PROJECT_DIR"])
    bundle = pathlib.Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["WRAPPER_NAME"]
    simulator = os.environ.get("EFFECTIVE_PLATFORM_NAME") == "-iphonesimulator"
    identity = None
    if os.environ.get("CODE_SIGNING_ALLOWED") != "NO":
        identity = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY") or ("-" if simulator else None)
        if not identity:
            raise SystemExit("A code signing identity is needed for a signed device build.")
    architecture = os.environ.get("CURRENT_ARCH") or os.environ.get("NATIVE_ARCH_ACTUAL", "arm64")
    frameworks = package(project, bundle, simulator, os.environ["PRODUCT_BUNDLE_IDENTIFIER"],
                         os.environ.get("IPHONEOS_DEPLOYMENT_TARGET", "26.0"), identity,
                         architecture)
    print(f"Packaged {len(frameworks)} Python extension frameworks.")


if __name__ == "__main__":
    main()
