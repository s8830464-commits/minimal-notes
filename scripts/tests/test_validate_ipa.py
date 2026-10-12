import importlib.util
import pathlib
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "validate_ipa", pathlib.Path(__file__).parents[1] / "validate_ipa.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class IPAValidationTests(unittest.TestCase):
    def make_ipa(self, *, platform=2, signature=False, executable_mode=0o100755,
                 display_name="Заметки", sdk=0x1B0200):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = pathlib.Path(temporary.name) / "test.ipa"
        commands = struct.pack("<6I", 0x32, 24, platform, 0x0F0000, sdk, 0)
        if signature:
            commands += struct.pack("<4I", 0x1D, 16, 0, 0)
        binary = struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 2,
                             2 if signature else 1, len(commands), 0, 0) + commands
        info = {
            "CFBundleIdentifier": "com.ivan.minimalnotes", "CFBundleExecutable": "NotesApp",
            "CFBundleSupportedPlatforms": ["iPhoneOS"], "CFBundlePackageType": "APPL",
            "CFBundleVersion": "2", "CFBundleShortVersionString": "1.0.1",
            "MinimumOSVersion": "15.0", "CFBundleDisplayName": display_name,
            "UILaunchScreen": {}, "UIApplicationSceneManifest": {},
        }
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/NotesApp.app/Info.plist", plistlib.dumps(info))
            entry = zipfile.ZipInfo("Payload/NotesApp.app/NotesApp")
            entry.create_system = 3
            entry.external_attr = executable_mode << 16
            archive.writestr(entry, binary)
        return path

    def test_valid_unsigned_device_package(self):
        result = validator.validate(self.make_ipa(), "27.2", True)
        self.assertEqual(result["sdk"], "27.2.0")
        self.assertTrue(result["requires_user_signing"])
        self.assertFalse(result["device_installation_tested"])

    def test_rejects_simulator_executable(self):
        with self.assertRaisesRegex(ValueError, "physical iOS"):
            validator.validate(self.make_ipa(platform=7))

    def test_rejects_wrong_sdk(self):
        with self.assertRaisesRegex(ValueError, "Expected SDK"):
            validator.validate(self.make_ipa(sdk=0x120000), "27.2")

    def test_rejects_stale_signature(self):
        with self.assertRaisesRegex(ValueError, "signature"):
            validator.validate(self.make_ipa(signature=True))

    def test_rejects_non_executable_binary(self):
        with self.assertRaisesRegex(ValueError, "permission"):
            validator.validate(self.make_ipa(executable_mode=0o100644))

    def test_catches_plist_regeneration(self):
        with self.assertRaisesRegex(ValueError, "Display name"):
            validator.validate(self.make_ipa(display_name=""), require_metadata=True)


if __name__ == "__main__":
    unittest.main()
