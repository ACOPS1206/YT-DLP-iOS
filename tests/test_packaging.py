import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("embed_python", pathlib.Path(__file__).resolve().parents[1] / "tools/embed_python.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PackagingTests(unittest.TestCase):
    def fixture(self, root):
        project, bundle = root / "project", root / "Example.app"
        framework = project / "Vendor/Python.xcframework"
        framework.mkdir(parents=True)
        common = framework / "lib/python3.13/encodings"
        common.mkdir(parents=True)
        (common / "__init__.py").write_text("# fixture\n")
        rows = []
        for identifier, simulator in (("ios-arm64", False), ("ios-arm64_x86_64-simulator", True)):
            base = framework / identifier / "lib-arm64/python3.13"
            (base / "lib-dynload").mkdir(parents=True)
            (base / "lib-dynload/_ssl.cpython-313-ios.so").write_bytes(identifier.encode())
            (base / "lib-dynload/_ssl.xcprivacy").write_bytes(plistlib.dumps({"NSPrivacyTracking": False}))
            row = {"LibraryIdentifier": identifier, "SupportedPlatform": "ios"}
            if simulator: row["SupportedPlatformVariant"] = "simulator"
            rows.append(row)
        (framework / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": rows}))
        (bundle / "app").mkdir(parents=True)
        return project, bundle

    def test_device_binary_relocation_and_loader_markers(self):
        with tempfile.TemporaryDirectory() as folder:
            project, bundle = self.fixture(pathlib.Path(folder))
            created = module.package(project, bundle, False, "dev.fixture.app", "26.0")
            binary = bundle / "Frameworks/_ssl.framework/_ssl"
            marker = bundle / "python/lib/python3.13/lib-dynload/_ssl.cpython-313-ios.fwork"
            origin = binary.with_name("_ssl.origin")
            self.assertEqual(binary.read_bytes(), b"ios-arm64")
            self.assertTrue((bundle / "python/lib/python3.13/encodings/__init__.py").exists())
            self.assertEqual(bundle / marker.read_text().strip(), binary)
            self.assertEqual(bundle / origin.read_text().strip(), marker)
            self.assertEqual(len(list(bundle.rglob("*.so"))), 0)
            self.assertTrue((created[0] / "PrivacyInfo.xcprivacy").exists())

    def test_simulator_selects_its_own_slice(self):
        with tempfile.TemporaryDirectory() as folder:
            project, bundle = self.fixture(pathlib.Path(folder))
            module.package(project, bundle, True, "dev.fixture.app", "26.0")
            self.assertEqual((bundle / "Frameworks/_ssl.framework/_ssl").read_bytes(), b"ios-arm64_x86_64-simulator")

    def test_repeat_packaging_restores_extension_markers(self):
        with tempfile.TemporaryDirectory() as folder:
            project, bundle = self.fixture(pathlib.Path(folder))
            for _ in range(2): module.package(project, bundle, False, "dev.fixture.app", "26.0")
            self.assertEqual(len(list(bundle.rglob("*.fwork"))), 1)


if __name__ == "__main__":
    unittest.main()
